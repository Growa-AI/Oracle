// payment_handler.mo
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Types "types";

module {
    type PaymentInfo = Types.PaymentInfo;
    type ErrorCode = Types.ErrorCode;
    
    // Interfaccia per il ledger canister
    public type Account = { owner : Principal; subaccount : ?[Nat8] };
    public type Tokens = { e8s : Nat64 };
    
    public type TransferArgs = {
        memo : Nat64;
        amount : Tokens;
        fee : Tokens;
        from_subaccount : ?[Nat8];
        to : Account;
        created_at_time : ?Nat64;
    };

    public type TransferResult = {
        #Ok : Nat64;
        #Err : {
            #InsufficientFunds : { balance: Tokens };
            #TxTooOld : { allowed_window_nanos: Nat64 };
            #TxCreatedInFuture;
            #TxDuplicate : { duplicate_of: Nat64 };
        };
    };

    public type ICPLedger = actor {
        transfer : TransferArgs -> async TransferResult;
        account_balance : query { account: Account } -> async Tokens;
    };

    public class PaymentHandler(ledgerCanisterId: Principal) {
        private let ledger: ICPLedger = actor(Principal.toText(ledgerCanisterId));
        private let DEFAULT_FEE : Tokens = { e8s = 10000 };
        private let TRANSFER_MEMO : Nat64 = 1234567890;

        public func processPayment(
            from: Principal,
            amount: Nat64,
            duration: Int // durata in secondi
        ) : async Result.Result<PaymentInfo, ErrorCode> {
            let payment_account: Account = {
                owner = from;
                subaccount = null;
            };

            // Verifica il saldo
            try {
                let balance = await ledger.account_balance({ account = payment_account });
                if (balance.e8s < amount + DEFAULT_FEE.e8s) {
                    return #err(#InsufficientFunds);
                };
            } catch (error) {
                return #err(#NetworkError(Error.message(error)));
            };

            // Prepara il trasferimento
            let transfer_args: TransferArgs = {
                memo = TRANSFER_MEMO;
                amount = { e8s = amount };
                fee = DEFAULT_FEE;
                from_subaccount = null;
                to = {
                    owner = Principal.fromActor(self);
                    subaccount = null;
                };
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            };

            // Esegui il trasferimento
            try {
                let result = await ledger.transfer(transfer_args);
                switch(result) {
                    case (#Ok(blockIndex)) {
                        let now = Time.now();
                        #ok({
                            amount = amount;
                            paid_at = now;
                            expires_at = now + duration * 1_000_000_000;
                            status = #Active;
                        })
                    };
                    case (#Err(#InsufficientFunds { balance })) {
                        #err(#InsufficientFunds)
                    };
                    case (#Err(#TxTooOld { allowed_window_nanos })) {
                        #err(#InvalidTransaction)
                    };
                    case (#Err(#TxCreatedInFuture)) {
                        #err(#InvalidTransaction)
                    };
                    case (#Err(#TxDuplicate { duplicate_of })) {
                        #err(#InvalidTransaction)
                    };
                };
            } catch (error) {
                #err(#NetworkError(Error.message(error)))
            };
        };

        public func refundPayment(
            to: Principal,
            amount: Nat64
        ) : async Result.Result<(), ErrorCode> {
            let transfer_args: TransferArgs = {
                memo = TRANSFER_MEMO;
                amount = { e8s = amount };
                fee = DEFAULT_FEE;
                from_subaccount = null;
                to = {
                    owner = to;
                    subaccount = null;
                };
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            };

            try {
                let result = await ledger.transfer(transfer_args);
                switch(result) {
                    case (#Ok(_)) { #ok(()) };
                    case (#Err(_)) { #err(#InvalidTransaction) };
                };
            } catch (error) {
                #err(#NetworkError(Error.message(error)))
            };
        };
    };
};
