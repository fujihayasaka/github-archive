function trigger(){
    var context = getContext();
    var collection = context.getCollection();
    var collectionLink = collection.getSelfLink();
    var response = context.getResponse();
    var errorCodes = { CONFLICT: 409 };
    var createdDocument = context.getRequest().getBody();

    var filterQuery =
    {
            'query' : 'SELECT sum(c.Quantity) as Quantity, sum(c.BilledAmount) as CurrentAmount FROM c where c.id != "budgetState"',
    };

    const budgetState = {
        id: 'budgetState',
        IsFullyFunded: false,
        TargetAmount: createdDocument.TargetAmount,
        Quantity: createdDocument.Quantity,
        CurrentAmount: createdDocument.BilledAmount,
        partitionKey: createdDocument.partitionKey
    };

    /*
    see lib/models/budget.go
        CurrentAmount float64
        Quantity 	float64
        IsFullyFunded bool
        TargetAmount float64
    */


    var submitted = collection.queryDocuments(collection.getSelfLink(), filterQuery, {},
    function (err, items) {
            if (err) throw new Error("Error" + err.message);
            if (items.length != 1) throw "unable to sum";

            budgetState.Quantity = items[0].Quantity + createdDocument.Quantity
            budgetState.CurrentAmount = items[0].CurrentAmount + createdDocument.BilledAmount
            budgetState.IsFullyFunded = budgetState.CurrentAmount >= createdDocument.TargetAmount

            tryCreate(budgetState, callback);
            response.setBody(budgetState)

    });
    if (!submitted) throw "unable to calculate budget";

    function tryCreate(doc, callback) {
        var isAccepted = collection.createDocument(collectionLink, doc, callback);
        if (!isAccepted) throw new Error("Unable to schedule create document");
    }

    // To replace the document, first issue a query to find it and then call replace.
    function tryReplace(doc, callback) {
        retrieveDoc(doc, null, function(retrievedDocs){
            var isAccepted = collection.replaceDocument(retrievedDocs[0]._self, doc, callback);
            if (!isAccepted) throw new Error("Unable to schedule replace document");
        });
    }

    function retrieveDoc(doc, continuation, callback) {
        var query = { query: "select * from root r where r.id = @id", parameters: [ {name: "@id", value: doc.id}]};
        var requestOptions = { continuation : continuation };
        var isAccepted = collection.queryDocuments(collectionLink, query, requestOptions, function(err, retrievedDocs, responseOptions) {
            if (err) throw err;

            if (retrievedDocs.length > 0) {
                callback(retrievedDocs);
            } else if (responseOptions.continuation) {
                // Conservative check for continuation. Not expected to hit in practice for the "id query"
                retrieveDoc(doc, responseOptions.continuation, callback);
            } else {
                throw new Error("Error in retrieving document: " + doc.id);
            }
            });
        if (!isAccepted) throw new Error("Unable to query documents");
    }

    // This is called when collection.createDocument is done in order to
    // process the result.
    function callback(err, doc, options) {
        if (err) {
            // Replace the document if status code is 409 and upsert is enabled
            if(err.number == errorCodes.CONFLICT) {
                return tryReplace(budgetState, callback);
            } else {
                throw err;
            }
        }
    }
}
