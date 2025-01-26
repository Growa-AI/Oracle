import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Nat32 "mo:base/Nat32";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

actor {
    private stable var admin : ?Principal = null;
    private type HashType = Text;
    private stable var treeEntries : [(Text, HashType)] = [];
    private stable var merkleRoots : [(HashType, [HashType])] = [];
    private var trees = HashMap.HashMap<Text, HashType>(0, Text.equal, Text.hash);
    private var proofs = HashMap.HashMap<HashType, [HashType]>(0, Text.equal, Text.hash);

    system func preupgrade() {
        treeEntries := Iter.toArray(trees.entries());
        merkleRoots := Iter.toArray(proofs.entries());
    };

    system func postupgrade() {
        trees := HashMap.fromIter<Text, HashType>(treeEntries.vals(), 0, Text.equal, Text.hash);
        proofs := HashMap.fromIter<HashType, [HashType]>(merkleRoots.vals(), 0, Text.equal, Text.hash);
    };

    public shared({caller}) func registerAdmin() : async Result.Result<Text, Text> {
        switch (admin) {
            case (?existing) { #err("Admin already registered") };
            case null {
                admin := ?caller;
                #ok("Admin registered successfully")
            }
        }
    };

    public shared({caller}) func createMerkleTree(data: [Text]) : async Result.Result<HashType, Text> {
        switch (admin) {
            case (?adminPrincipal) {
                if (caller != adminPrincipal) {
                    return #err("Only admin can create Merkle Tree");
                };

                let leaves = Buffer.Buffer<HashType>(data.size());
                
                // Create leaf hashes and save
                for (item in data.vals()) {
                    let hash = makeHash(item);
                    leaves.add(hash);
                    trees.put(item, hash);
                };

                var currentLevel = leaves;
                while (currentLevel.size() > 1) {
                    let nextLevel = Buffer.Buffer<HashType>(0);
                    var i = 0;
                    while (i < currentLevel.size()) {
                        let left = currentLevel.get(i);
                        let right = if (i + 1 < currentLevel.size()) {
                            currentLevel.get(i + 1)
                        } else {
                            left
                        };
                        nextLevel.add(hashPair(left, right));
                        i += 2;
                    };
                    currentLevel := nextLevel;
                };

                if (currentLevel.size() > 0) {
                    let root = currentLevel.get(0);
                    let proof = Buffer.toArray(leaves);
                    proofs.put(root, proof);
                    #ok(root)
                } else {
                    #err("No data provided")
                }
            };
            case null { #err("Admin not registered") }
        }
    };

    public query func getMerkleProof(data: Text) : async ?[HashType] {
        switch (trees.get(data)) {
            case (?hash) {
                for ((root, proof) in proofs.entries()) {
                    let exists = Array.find<HashType>(proof, func x = x == hash);
                    switch(exists) {
                        case (?_) {
                            return ?Array.filter<HashType>(proof, func x = x != hash);
                        };
                        case null {};
                    };
                };
            };
            case null {};
        };
        null
    };

    public query func verifyProof(data: Text, proof: [HashType]) : async Bool {
        switch (trees.get(data)) {
            case (?hash) {
                var currentHash = hash;
                for (proofElement in proof.vals()) {
                    if (currentHash < proofElement) {
                        currentHash := makeHash(currentHash # proofElement);
                    } else {
                        currentHash := makeHash(proofElement # currentHash);
                    };
                };
                
                for ((root, _) in proofs.entries()) {
                    if (root == currentHash) return true;
                };
            };
            case null {};
        };
        false
    };

    public query func verifyDataInTree(data: Text, rootHash: Text) : async Bool {
        switch (trees.get(data)) {
            case (?hash) {
                switch (proofs.get(rootHash)) {
                    case (?proof) {
                        var currentHash = hash;
                        for (proofElement in Array.filter<HashType>(proof, func x = x != hash).vals()) {
                            if (currentHash < proofElement) {
                                currentHash := makeHash(currentHash # proofElement);
                            } else {
                                currentHash := makeHash(proofElement # currentHash);
                            };
                        };
                        currentHash == rootHash
                    };
                    case null { false };
                };
            };
            case null { false };
        }
    };

    public query func getRoot() : async ?HashType {
        for ((root, _) in proofs.entries()) {
            return ?root;
        };
        null
    };

    private func hashPair(left: HashType, right: HashType) : HashType {
        if (left < right) {
            makeHash(left # right)
        } else {
            makeHash(right # left)
        }
    };

    private func makeHash(data: Text) : Text {
        Nat32.toText(Text.hash(data))
    };
}
