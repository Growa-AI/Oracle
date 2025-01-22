// oracle_nft.mo
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Types "types";
import HttpClient "http_client";
import PaymentHandler "payment_handler";

actor OracleNFT {
    type DataPackage = Types.DataPackage;
    type NFTMetadata = Types.NFTMetadata;
    type PaymentInfo = Types.PaymentInfo;
    type SecurityConfig = Types.SecurityConfig;
    type ErrorCode = Types.ErrorCode;
    type RequestStatus = Types.RequestStatus;
    type TransferRecord = Types.TransferRecord;

    // NFT State
    private stable var nextTokenId: Nat = 0;
    private var nftMetadata = HashMap.HashMap<Nat, NFTMetadata>(0, Nat.equal, Hash.hash);
    private var userTokens = HashMap.HashMap<Principal, Buffer.Buffer<Nat>>(0, Principal.equal, Principal.hash);
    private var packageData = HashMap.HashMap<Text, DataPackage>(0, Text.equal, Text.hash);
    
    // System State
    private stable var owner: ?Principal = null;
    private var httpClient: ?HttpClient.HttpClient = null;
    private var paymentHandler: ?PaymentHandler.PaymentHandler = null;
    private var securityConfig: SecurityConfig = {
        max_retries = 3;
        timeout_ms = 5000;
        max_response_size = 1024 * 1024;
        allowed_domains = [];
        required_headers = [];
        rate_limit_per_day = 100;
        min_payment_amount = 100_000;
        key_rotation_period = 86400;
    };

    // Initialize system
    public shared(msg) func initialize(
        ledgerCanisterId: Principal,
        config: ?SecurityConfig
    ) : async Result.Result<(), ErrorCode> {
        if (Option.isSome(owner)) {
            return #err(#UnauthorizedAccess);
        };

        owner := ?msg.caller;

        // Setup configuration
        switch(config) {
            case null { };
            case (?newConfig) { securityConfig := newConfig; };
        };

        // Initialize components
        httpClient := ?HttpClient.HttpClient(securityConfig);
        paymentHandler := ?PaymentHandler.PaymentHandler(ledgerCanisterId);

        #ok(())
    };

    // Request and mint NFT
    public shared(msg) func requestDataPackageNFT(
        payment_amount: Nat64,
        request_params: Text
    ) : async Result.Result<Nat, ErrorCode> {
        // Process payment
        let payment = switch(paymentHandler) {
            case null { return #err(#InvalidResponse) };
            case (?handler) {
                switch(await handler.processPayment(msg.caller, payment_amount, 30 * 24 * 3600)) {
                    case (#err(e)) { return #err(e) };
                    case (#ok(info)) { info };
                };
            };
        };

        // Request data package
        let package = await requestDataPackage(request_params);
        switch(package) {
            case (#err(e)) { 
                // Refund payment on error
                ignore await refundPayment(msg.caller, payment_amount);
                return #err(e);
            };
            case (#ok(data_package)) {
                // Mint NFT
                let token_id = nextTokenId;
                nextTokenId += 1;

                let metadata: NFTMetadata = {
                    token_id = token_id;
                    owner = msg.caller;
                    created_at = Time.now();
                    package_id = data_package.metadata.package_id;
                    payment_info = payment;
                    transfer_history = [{
                        from = Principal.fromActor(self);
                        to = msg.caller;
                        timestamp = Time.now();
                        price = ?payment_amount;
                    }];
                };

                nftMetadata.put(token_id, metadata);
                packageData.put(data_package.metadata.package_id, data_package);

                // Update user tokens
                switch (userTokens.get(msg.caller)) {
                    case null {
                        let newBuf = Buffer.Buffer<Nat>(1);
                        newBuf.add(token_id);
                        userTokens.put(msg.caller, newBuf);
                    };
                    case (?buf) {
                        buf.add(token_id);
                    };
                };

                #ok(token_id)
            };
        };
    };

    // Transfer NFT
    public shared(msg) func transferNFT(
        to: Principal,
        token_id: Nat,
        price: ?Nat64
    ) : async Result.Result<(), ErrorCode> {
        switch (nftMetadata.get(token_id)) {
            case null { return #err(#InvalidPackage) };
            case (?metadata) {
                if (metadata.owner != msg.caller) {
                    return #err(#UnauthorizedAccess);
                };

                // Update metadata
                let newTransfer: TransferRecord = {
                    from = msg.caller;
                    to = to;
                    timestamp = Time.now();
                    price = price;
                };

                let updatedMetadata: NFTMetadata = {
                    token_id = metadata.token_id;
                    owner = to;
                    created_at = metadata.created_at;
                    package_id = metadata.package_id;
                    payment_info = metadata.payment_info;
                    transfer_history = Array.append(metadata.transfer_history, [newTransfer]);
                };

                nftMetadata.put(token_id, updatedMetadata);

                // Update user token mappings
                switch (userTokens.get(msg.caller)) {
                    case null { };
                    case (?fromBuf) {
                        let newFromBuf = Buffer.Buffer<Nat>(fromBuf.size());
                        for (id in fromBuf.vals()) {
                            if (id != token_id) {
                                newFromBuf.add(id);
                            };
                        };
                        userTokens.put(msg.caller, newFromBuf);
                    };
                };

                switch (userTokens.get(to)) {
                    case null {
                        let newBuf = Buffer.Buffer<Nat>(1);
                        newBuf.add(token_id);
                        userTokens.put(to, newBuf);
                    };
                    case (?toBuf) {
                        toBuf.add(token_id);
                    };
                };

                #ok(())
            };
        };
    };

    // Query functions
    public query func getNFTMetadata(token_id: Nat) : async Result.Result<NFTMetadata, ErrorCode> {
        switch(nftMetadata.get(token_id)) {
            case null { #err(#InvalidPackage) };
            case (?metadata) { #ok(metadata) };
        }
    };

    public query func getDataPackage(token_id: Nat) : async Result.Result<DataPackage, ErrorCode> {
        switch(nftMetadata.get(token_id)) {
            case null { #err(#InvalidPackage) };
            case (?metadata) {
                switch(packageData.get(metadata.package_id)) {
                    case null { #err(#InvalidPackage) };
                    case (?package) { #ok(package) };
                };
            };
        }
    };

    public query func getUserTokens(user: Principal) : async [Nat] {
        switch (userTokens.get(user)) {
            case null { [] };
            case (?buf) { Buffer.toArray(buf) };
        }
    };

    public query func getTokenTransferHistory(token_id: Nat) : async Result.Result<[TransferRecord], ErrorCode> {
        switch(nftMetadata.get(token_id)) {
            case null { #err(#InvalidPackage) };
            case (?metadata) { #ok(metadata.transfer_history) };
        }
    };

    // Internal functions
    private func requestDataPackage(params: Text) : async Result.Result<DataPackage, ErrorCode> {
        switch(httpClient) {
            case null { #err(#InvalidResponse) };
            case (?client) {
                let headers = [
                    { name = "Content-Type"; value = "application/json" },
                    { name = "X-Request-ID"; value = generateRequestId() }
                ];

                let response = await client.post(
                    "https://api.backend.com/generate-package",
                    headers,
                    ?Text.encodeUtf8(params),
                    null
                );

                switch(response) {
                    case (#err(e)) { #err(e) };
                    case (#ok(httpResponse)) {
                        switch(httpResponse.body) {
                            case null { #err(#InvalidResponse) };
                            case (?body) {
                                // Parse response into DataPackage
                                try {
                                    #ok(parseDataPackage(body))
                                } catch (e) {
                                    #err(#InvalidResponse)
                                }
                            };
                        };
                    };
                };
            };
        };
    };

    private func refundPayment(to: Principal, amount: Nat64) : async Result.Result<(), ErrorCode> {
        switch(paymentHandler) {
            case null { #err(#InvalidResponse) };
            case (?handler) {
                await handler.refundPayment(to, amount)
            };
        }
    };

    private func parseDataPackage(body: Blob) : DataPackage {
        // In produzione, implementare il parsing JSON appropriato
        // Questo è un placeholder
        {
            raw_data = [];
            processed_data = {
                min = 0.0;
                max = 0.0;
                avg = 0.0;
                median = 0.0;
            };
            metadata = {
                package_id = generatePackageId();
                created_at = Time.now();
                expires_at = Time.now() + 30 * 24 * 3600 * 1000000000;
                data_hash = "hash";
                checksum = "checksum";
                schema_version = 1;
                source_device = "device";
                data_type = "type";
                sample_rate = 1;
                unit = "unit";
                location = null;
            };
            visualizations = [];
        }
    };

    private func generateRequestId() : Text {
        "req_" # Int.toText(Time.now())
    };

    private func generatePackageId() : Text {
        "pkg_" # Int.toText(Time.now())
    };

    // Admin functions
    public shared(msg) func updateSecurityConfig(newConfig: SecurityConfig) : async Result.Result<(), ErrorCode> {
        if (not isAdmin(msg.caller)) {
            return #err(#UnauthorizedAccess);
        };

        securityConfig := newConfig;
        httpClient := ?HttpClient.HttpClient(newConfig);
        #ok(())
    };

    public shared(msg) func withdrawBalance(amount: Nat64) : async Result.Result<(), ErrorCode> {
        if (not isAdmin(msg.caller)) {
            return #err(#UnauthorizedAccess);
        };

        switch(paymentHandler) {
            case null { #err(#InvalidResponse) };
            case (?handler) {
                await handler.refundPayment(msg.caller, amount)
            };
        }
    };

    // Helper functions
    private func isAdmin(caller: Principal) : Bool {
        switch(owner) {
            case null { false };
            case (?admin) { Principal.equal(caller, admin) };
        }
    };
};
