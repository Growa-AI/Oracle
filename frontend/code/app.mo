import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";

actor AdminContract {
    public type Sector = {
        #Banking;
        #Insurance;
        #Vendor;
        #Research;
        #Developer;
    };

    public type Subscription = {
        expiryTime: Time.Time;
        active: Bool;
        totalMonths: Nat;  // Totale mesi di sottoscrizione
    };

    private stable var currentAdmin: ?Principal = null;
    private stable var subscriptionCost: Nat = 0;
    private stable var contractBalance: Nat = 0;  // Bilancio del contratto
    
    private let users = HashMap.HashMap<Principal, Sector>(0, Principal.equal, Principal.hash);
    private let subscriptions = HashMap.HashMap<Principal, Subscription>(0, Principal.equal, Principal.hash);

    // [Le funzioni di gestione admin e utenti rimangono invariate...]
    public shared(msg) func becomeAdmin() : async Bool {
        switch(currentAdmin) {
            case (null) {
                currentAdmin := ?msg.caller;
                return true;
            };
            case (?admin) {
                return false;
            };
        };
    };

    public shared(msg) func transferAdmin(newAdmin: Principal) : async Bool {
        switch(currentAdmin) {
            case (?admin) {
                if (msg.caller == admin) {
                    currentAdmin := ?newAdmin;
                    return true;
                } else {
                    return false;
                };
            };
            case (null) {
                return false;
            };
        };
    };

    public query func getCurrentAdmin() : async ?Principal {
        return currentAdmin;
    };

    // Funzione per cambiare il costo dell'abbonamento (solo admin)
    public shared(msg) func setSubscriptionCost(newCost: Nat) : async Bool {
        switch(currentAdmin) {
            case (?admin) {
                if (msg.caller == admin) {
                    subscriptionCost := newCost;
                    return true;
                };
            };
            case (null) {};
        };
        return false;
    };

    // Funzione per ottenere il costo attuale dell'abbonamento
    public query func getSubscriptionCost() : async Nat {
        return subscriptionCost;
    };

    public shared(msg) func register(sector: Sector) : async Bool {
        switch (users.get(msg.caller)) {
            case (?existingSector) {
                return false;
            };
            case (null) {
                users.put(msg.caller, sector);
                return true;
            };
        };
    };

    public shared(msg) func changeSector(newSector: Sector) : async Bool {
        switch (users.get(msg.caller)) {
            case (?currentSector) {
                users.put(msg.caller, newSector);
                return true;
            };
            case (null) {
                return false;
            };
        };
    };

    // Funzione per ottenere il settore di un utente
    public query func getUserSector(user: Principal) : async ?Sector {
        return users.get(user);
    };

    // Funzione per verificare se un utente è registrato
    public query func isUserRegistered(user: Principal) : async Bool {
        switch (users.get(user)) {
            case (?sector) { true };
            case (null) { false };
        };
    };

    // Funzione per sottoscrivere o rinnovare l'abbonamento (payable)
    public shared(msg) func subscribe() : async Result.Result<Text, Text> {
        // Verifica che l'utente sia registrato
        switch (users.get(msg.caller)) {
            case (null) {
                return #err("Utente non registrato");
            };
            case (?sector) {
                // Verifica il pagamento
                let payment = Cycles.available();
                if (payment < subscriptionCost) {
                    return #err("Pagamento insufficiente");
                };
                
                // Accetta il pagamento
                let accepted = Cycles.accept(subscriptionCost);
                contractBalance += accepted;

                let currentTime = Time.now();
                
                switch (subscriptions.get(msg.caller)) {
                    case (null) {
                        // Nuovo abbonamento
                        let expiryTime = currentTime + 2_592_000_000_000_000;
                        subscriptions.put(msg.caller, {
                            expiryTime = expiryTime;
                            active = true;
                            totalMonths = 1;
                        });
                    };
                    case (?subscription) {
                        // Rinnovo abbonamento
                        let newExpiryTime = Int.max(subscription.expiryTime, currentTime) + 2_592_000_000_000_000;
                        subscriptions.put(msg.caller, {
                            expiryTime = newExpiryTime;
                            active = true;
                            totalMonths = subscription.totalMonths + 1;
                        });
                    };
                };
                return #ok("Abbonamento sottoscritto con successo");
            };
        };
    };

    // Funzione per l'admin per prelevare i cicli
    public shared(msg) func withdrawCycles(amount: Nat) : async Result.Result<Text, Text> {
        switch(currentAdmin) {
            case (?admin) {
                if (msg.caller != admin) {
                    return #err("Solo l'amministratore può prelevare i fondi");
                };

                if (contractBalance < amount) {
                    return #err("Saldo insufficiente");
                };

                Cycles.add(amount);  // Aggiunge i cicli al messaggio
                // Crea un contenitore per i cicli
                let receiver = actor(Principal.toText(admin)) : actor {
                    wallet_receive : () -> async Nat;
                };
                
                try {
                    let received = await receiver.wallet_receive();
                    contractBalance -= amount;
                    return #ok("Fondi prelevati con successo");
                } catch (e) {
                    return #err("Errore durante il trasferimento: " # Error.message(e));
                };
            };
            case (null) {
                return #err("Nessun amministratore impostato");
            };
        };
    };

    // Funzione per ottenere il bilancio del contratto (solo admin)
    public shared(msg) func getContractBalance() : async Result.Result<Nat, Text> {
        switch(currentAdmin) {
            case (?admin) {
                if (msg.caller != admin) {
                    return #err("Solo l'amministratore può vedere il bilancio");
                };
                return #ok(contractBalance);
            };
            case (null) {
                return #err("Nessun amministratore impostato");
            };
        };
    };

    // [Altre funzioni di gestione sottoscrizioni rimangono invariate...]
    public query func getTotalSubscriptionMonths(user: Principal) : async Nat {
        switch (subscriptions.get(user)) {
            case (?subscription) {
                return subscription.totalMonths;
            };
            case (null) {
                return 0;
            };
        };
    };

    public shared(msg) func addSubscriptionMonths(user: Principal, months: Nat) : async Bool {
        switch(currentAdmin) {
            case (?admin) {
                if (msg.caller != admin) {
                    return false;
                };
            };
            case (null) {
                return false;
            };
        };

        switch (users.get(user)) {
            case (null) {
                return false;
            };
            case (?sector) {
                let currentTime = Time.now();
                let monthsInNanos = Int.mul(months, 2_592_000_000_000_000);
                
                switch (subscriptions.get(user)) {
                    case (null) {
                        subscriptions.put(user, {
                            expiryTime = currentTime + monthsInNanos;
                            active = true;
                            totalMonths = months;
                        });
                    };
                    case (?subscription) {
                        let newExpiryTime = Int.max(subscription.expiryTime, currentTime) + monthsInNanos;
                        subscriptions.put(user, {
                            expiryTime = newExpiryTime;
                            active = true;
                            totalMonths = subscription.totalMonths + months;
                        });
                    };
                };
                return true;
            };
        };
    };
};
