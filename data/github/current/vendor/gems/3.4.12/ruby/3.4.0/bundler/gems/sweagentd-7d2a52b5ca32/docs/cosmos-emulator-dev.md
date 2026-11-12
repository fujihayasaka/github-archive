# Using Cosmos DB Emulator for Development

This guide explains how to use the Cosmos DB emulator in your development environment instead of the in-memory store. Using the emulator helps catch race conditions and other issues that only appear with real Cosmos DB.

## Quick Start

1. **Start the emulator:**
   ```bash
   script/cosmos-dev start
   ```

2. **Run your application:**
   ```bash
   script/server
   # or
   overmind start
   ```

The application will automatically detect and use the running emulator.

## Why Use the Emulator?

The in-memory store used as a fallback in development doesn't replicate all the behaviors of Cosmos DB:

- **Race conditions**: Cosmos DB's consistency models and timing can expose race conditions not seen with in-memory stores
- **Connection handling**: Network timeouts, retries, and connection pooling behaviors
- **Serialization**: JSON serialization/deserialization edge cases
- **Partition key behavior**: How partition keys affect operations
- **ETags and optimistic concurrency**: Proper testing of concurrent updates
- **Embedded Data Explorer**: You can access `https://localhost:8081/_explorer/index.html` to see a Data Explorer to get a better view of the shape of our data

## Commands

### Start the emulator
```bash
script/cosmos-dev start
```
This will:
- Pull the Cosmos DB emulator Docker image if needed
- Start the emulator container on port 8081
- Wait for the emulator to be ready
- Display connection information

### Check status
```bash
script/cosmos-dev status
```

### View logs
```bash
script/cosmos-dev logs
```

### Stop the emulator
```bash
script/cosmos-dev stop
```

### Reset the emulator (fresh start)
```bash
script/cosmos-dev reset
```

## Configuration

### Automatic Configuration

When you start the emulator with `script/cosmos-dev start`, it will display the connection details:

```
Endpoint: http://localhost:8081/
Key: C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==
Connection String: AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==
```

### Manual Configuration

If you want to explicitly configure your environment to use the emulator:

1. **Using .env file:**
   ```bash
   cp .env.cosmos-dev .env
   ```

2. **Or set environment variables:**
   ```bash
   export AZURE_COSMOSDB_ENDPOINT="http://localhost:8081/"
   export AZURE_COSMOSDB_CONNECTION_STRING="AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
   ```

### Fallback Behavior

The application tries to connect to stores in this order:

1. **Explicit Cosmos DB configuration** (if `AZURE_COSMOSDB_ENDPOINT` or `AZURE_COSMOSDB_CONNECTION_STRING` is set)
2. **Cosmos DB emulator** (if running on localhost:8081)
3. **In-memory store** (fallback for development only)

## Using with Overmind

The `Procfile` includes a `cosmos` process that automatically starts the emulator:

```bash
# Start all services including Cosmos emulator
overmind start

# Start only specific services
overmind start http twirp cosmos

# Start without the emulator (uses memory store)
overmind start http twirp
```

## Troubleshooting

### Container fails to start
- Ensure Docker is running: `docker info`
- Check if port 8081 is available: `lsof -i :8081`
- Try resetting: `script/cosmos-dev reset`

### Application still uses memory store
- Verify emulator is running: `script/cosmos-dev status`
- Check application logs for connection attempts
- Ensure no conflicting environment variables are set
- Make sure the required DB Containers are created

### Emulator is slow to start
- The emulator can take 30-60 seconds to become ready
- Use `script/cosmos-dev logs` to monitor startup progress
- Consider keeping the emulator running between development sessions

### SSL/TLS issues
The emulator uses a self-signed certificate. The Azure SDK handles this automatically, but if you encounter SSL issues:
- Ensure you're using `https://localhost:8081/` (not http)
- The emulator key is the standard development key published by Microsoft

## Performance Considerations

- **Startup time**: The emulator takes time to start. Consider keeping it running.
- **Resource usage**: The emulator uses more resources than the in-memory store.
- **Data persistence**: Data is reset when the container restarts (by design for development).

## Integration with Tests

For integration tests that need Cosmos DB, use the existing test container infrastructure:

```go
// In tests
func TestWithCosmos(t *testing.T) {
    container := testcontainer.NewCosmosTestContainer(t)
    client := container.Client()
    // ... test code
}
```

The emulator is primarily for development workflow, not automated testing.