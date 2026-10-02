// ========================================
// FEEDBACK FUNCTION UNIT TESTS
// Tests the Feedback Function without
// connecting to real Azure Table Storage.
// ========================================

const { TableClient } = require("@azure/data-tables");

// Mock the Azure Table Storage SDK.
// This replaces the real Azure connection
// with a controlled test version.
jest.mock("@azure/data-tables", () => ({
    TableClient: {
        fromConnectionString: jest.fn()
    }
}));

const feedbackFunction =
    require("../FeedbackFunction/index");

// ========================================
// TEST SETUP
// ========================================

describe("Feedback Function", () => {

    let context;
    let mockCreateEntity;

    beforeEach(() => {

        // Create a fresh mock for Azure's
        // createEntity method before each test.
        mockCreateEntity = jest.fn().mockResolvedValue({});

        TableClient.fromConnectionString.mockReturnValue({
            createEntity: mockCreateEntity
        });

        // Mock the Azure Function context.
        context = {
            log: jest.fn()
        };

        context.log.error = jest.fn();

        // Provide a fake connection string.
        // No real Azure credentials are used.
        process.env.FEEDBACK_STORAGE_CONNECTION =
            "mock-storage-connection";

        jest.clearAllMocks();
    });

    afterEach(() => {
        delete process.env.FEEDBACK_STORAGE_CONNECTION;
    });

    // ========================================
    // TEST 1 - MISSING MESSAGE
    // ========================================

    test("returns 400 when feedback message is missing", async () => {

        const req = {
            body: {}
        };

        await feedbackFunction(context, req);

        expect(context.res.status).toBe(400);

        expect(context.res.body).toEqual({
            error: "Feedback message is required."
        });

        expect(
            TableClient.fromConnectionString
        ).not.toHaveBeenCalled();

        expect(mockCreateEntity).not.toHaveBeenCalled();
    });

    // ========================================
    // TEST 2 - WHITESPACE MESSAGE
    // ========================================

    test("returns 400 when feedback contains only whitespace", async () => {

        const req = {
            body: {
                message: "   "
            }
        };

        await feedbackFunction(context, req);

        expect(context.res.status).toBe(400);

        expect(context.res.body).toEqual({
            error: "Feedback message is required."
        });

        expect(mockCreateEntity).not.toHaveBeenCalled();
    });

    // ========================================
    // TEST 3 - MISSING STORAGE CONFIGURATION
    // ========================================

    test("returns 500 when storage configuration is missing", async () => {

        delete process.env.FEEDBACK_STORAGE_CONNECTION;

        const req = {
            body: {
                message: "Valid feedback"
            }
        };

        await feedbackFunction(context, req);

        expect(context.res.status).toBe(500);

        expect(context.res.body).toEqual({
            error: "Storage configuration is missing."
        });

        expect(mockCreateEntity).not.toHaveBeenCalled();
    });

    // ========================================
    // TEST 4 - VALID FEEDBACK
    // ========================================

    test("stores valid feedback and returns 200", async () => {

        const req = {
            body: {
                message: "  Useful feedback  "
            }
        };

        await feedbackFunction(context, req);

        expect(
            TableClient.fromConnectionString
        ).toHaveBeenCalledWith(
            "mock-storage-connection",
            "FeedbackSubmissions"
        );

        expect(mockCreateEntity).toHaveBeenCalledTimes(1);

        const savedEntity =
            mockCreateEntity.mock.calls[0][0];

        expect(savedEntity.partitionKey).toBe("feedback");

        expect(savedEntity.message).toBe(
            "Useful feedback"
        );

        expect(savedEntity.rowKey).toBeDefined();

        expect(savedEntity.submittedAt).toBeDefined();

        expect(context.res.status).toBe(200);

        expect(context.res.body).toEqual({
            message: "Feedback received successfully."
        });
    });
});