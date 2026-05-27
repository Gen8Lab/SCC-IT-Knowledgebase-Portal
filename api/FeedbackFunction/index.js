// ========================================
// FEEDBACK FUNCTION
// Receives feedback from the frontend,
// validates the request and stores the
// submission inside Azure Table Storage.
// ========================================

const { TableClient } = require("@azure/data-tables");

module.exports = async function (context, req) {

    context.log("Feedback function triggered.");

    // ========================================
    // READ FEEDBACK MESSAGE
    // ========================================

    const feedback = req.body;

    // ========================================
    // VALIDATE REQUEST
    // ========================================

    if (!feedback || !feedback.message) {

        context.res = {
            status: 400,
            body: {
                error: "Feedback message is required."
            }
        };

        return;
    }

    // ========================================
    // CONNECT TO AZURE TABLE STORAGE
    // ========================================

    const connectionString =
        process.env.AzureWebJobsStorage;

    const tableName = "FeedbackSubmissions";

    const client = TableClient.fromConnectionString(
        connectionString,
        tableName
    );

    // ========================================
    // CREATE FEEDBACK RECORD
    // ========================================

    const entity = {

        partitionKey: "feedback",

        rowKey: Date.now().toString(),

        message: feedback.message,

        submittedAt: new Date().toISOString()
    };

    // ========================================
    // SAVE TO TABLE STORAGE
    // ========================================

    await client.createEntity(entity);

    context.log("Feedback saved to table storage.");

    // ========================================
    // RETURN SUCCESS RESPONSE
    // ========================================

    context.res = {

        status: 200,

        body: {
            message: "Feedback received successfully."
        }
    };
};
