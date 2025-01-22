// http_client.mo
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import IC "mo:base/IC";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Types "types";

module {
    type HttpHeader = Types.HttpHeader;
    type HttpResponse = Types.HttpResponse;
    type ErrorCode = Types.ErrorCode;
    type SecurityConfig = Types.SecurityConfig;

    public class HttpClient(config: SecurityConfig) {
        private let ic : IC.Self = actor "aaaaa-aa";
        private var retryCount = 0;

        public func get(
            url: Text,
            headers: [HttpHeader],
            transform: ?Blob
        ) : async Result.Result<HttpResponse, ErrorCode> {
            await makeRequest(url, headers, null, #get, transform);
        };

        public func post(
            url: Text,
            headers: [HttpHeader],
            body: ?Blob,
            transform: ?Blob
        ) : async Result.Result<HttpResponse, ErrorCode> {
            await makeRequest(url, headers, body, #post, transform);
        };

        private func makeRequest(
            url: Text,
            headers: [HttpHeader],
            body: ?Blob,
            method: {#get; #post; #head},
            transform: ?Blob
        ) : async Result.Result<HttpResponse, ErrorCode> {
            if (retryCount >= config.max_retries) {
                return #err(#NetworkError("Max retries exceeded"));
            };

            // Validate URL
            if (not validateUrl(url)) {
                return #err(#SecurityViolation);
            };

            // Add required headers
            let allHeaders = Array.append(
                headers,
                Array.map<HttpHeader, HttpHeader>(
                    config.required_headers,
                    func (h: HttpHeader): HttpHeader { h }
                )
            );

            let request = {
                url = url;
                max_response_bytes = ?config.max_response_size;
                headers = allHeaders;
                body = body;
                method = method;
                transform = transform;
            };

            try {
                let response = await ic.http_request(request);
                
                switch(validateResponse(response)) {
                    case (#err(error)) {
                        // Retry on temporary errors
                        if (isTemporaryError(error)) {
                            retryCount += 1;
                            return await makeRequest(url, headers, body, method, transform);
                        };
                        return #err(error);
                    };
                    case (#ok(_)) { };
                };

                retryCount := 0;
                #ok({
                    status = response.status;
                    headers = response.headers;
                    body = response.body;
                })
            } catch (error) {
                if (retryCount < config.max_retries) {
                    retryCount += 1;
                    return await makeRequest(url, headers, body, method, transform);
                };
                #err(#NetworkError(Error.message(error)))
            };
        };

        // Validation Functions
        private func validateUrl(url: Text) : Bool {
            let validDomain = Array.find<Text>(
                config.allowed_domains,
                func(domain: Text) : Bool {
                    Text.contains(url, #text domain)
                }
            );
            Option.isSome(validDomain)
        };

        private func validateResponse(response: HttpResponse) : Result.Result<(), ErrorCode> {
            // Check status code
            if (response.status < 200 or response.status >= 500) {
                return #err(#NetworkError("Invalid status code: " # Nat.toText(response.status)));
            };

            // Verify security headers
            let hasSecurityHeaders = Array.find<HttpHeader>(
                response.headers,
                func(header: HttpHeader) : Bool {
                    header.name == "X-Security-Checksum"
                }
            );

            if (Option.isNull(hasSecurityHeaders)) {
                return #err(#SecurityViolation);
            };

            // Check response size
            switch(response.body) {
                case null { return #ok(()); };
                case (?body) {
                    if (body.size() > config.max_response_size) {
                        return #err(#InvalidResponse);
                    };
                };
            };

            #ok(())
        };

        private func isTemporaryError(error: ErrorCode) : Bool {
            switch(error) {
                case (#NetworkError(msg)) {
                    Text.contains(msg, #text "timeout") or
                    Text.contains(msg, #text "temporary") or
                    Text.contains(msg, #text "overloaded")
                };
                case (_) { false };
            }
        };
    };
};
