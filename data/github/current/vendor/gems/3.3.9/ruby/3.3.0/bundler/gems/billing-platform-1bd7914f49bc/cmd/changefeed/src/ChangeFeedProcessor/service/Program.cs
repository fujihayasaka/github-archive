
using Microsoft.Extensions.Configuration;
using Microsoft.Azure.Cosmos;
using StatsdClient;
using Microsoft.Extensions.Logging;

using BillingPlatform.ChangeFeedProcessor.Processors;


namespace BillingPlatform.ChangeFeedProcessor;
class Program
{
  // Read ENV variables to connect to CosmosDB
  #region [ Environment Variables ]
  private const string EnvSourceCosmosConnectionString = "COSMOS_CONN_STR";
  private const string EnvSourceCosmosDB = "COSMOS_DB";
  private const string EnvSourceContainerName = "COSMOS_CONTAINER";
  private const string STATS_ADDR = "STATS_ADDR";
  #endregion

  private Guid instanceUUID = Guid.NewGuid();
  private static readonly string version = "v4";
  private bool dirtyExit = false;
  private CustomerMonthlyUsageRollupProcessor? customerMonthlyUsageRollupProcessor = null;

  // lease container keeps track of processing changes across changefeed workers
  private static readonly string lease = string.Format("lease-{0}", version);

  static async Task Main()
  {
    var program = new Program();

    /*
        Kubernetes readiness prob. Service will create a file when the service is ready to receive changes.
        When the service is shutting down, the file will be deleted. This will be used for the kubernetes readiness and liveness probes.
    */
    File.WriteAllText("/tmp/console-running", "true");

   var loggerFactory = LoggerFactory.Create(builder =>
    {
      builder.AddOpenTelemetry(options =>
      {
        options.AddGHExporter();

      });
      }
    );
    var logger = loggerFactory.CreateLogger<Program>();

    var config = new ConfigurationBuilder().AddEnvironmentVariables().Build();
    logger.LogInformation($"Starting console app!");

    try
    {
      var connectionString = config.GetSection(EnvSourceCosmosConnectionString).Value;
      if (string.IsNullOrEmpty(connectionString))
      {
        throw new ArgumentException("Connection string is null or empty.");
      }

      var (accountEndpoint, accountKey) = GetElementsFromConnectionString(connectionString);
      var databaseName = config.GetSection(EnvSourceCosmosDB).Value;
      var monitoredContainerName = config.GetSection(EnvSourceContainerName).Value;

      var client = new CosmosClient(accountEndpoint, accountKey);
      var monitoredContainer = client.GetContainer(databaseName, monitoredContainerName);

      // create a new lease container if it doesn't exist to store change feed history
      var leaseContainer = await client.GetDatabase(databaseName).CreateContainerIfNotExistsAsync(lease, "/partitionKey");
      var monthlyCustomerRollupContainer = await client.GetDatabase(databaseName).CreateContainerIfNotExistsAsync(string.Format("rollups-{0}", CustomerMonthlyUsageRollupProcessor.version), "/partitionKey");

      string statsAddr = config.GetSection(STATS_ADDR).Value ?? "localhost:8125"; // fall back to localhost:8125 per datadog docs;
      string[] splitStatsAddr = statsAddr.Split(":");
      string addr = splitStatsAddr[0];
      int port = int.Parse(splitStatsAddr[1]);
      var dogstatsdConfig = new StatsdConfig
      {
          StatsdServerName = addr,
          StatsdPort = port,
          Prefix = "billing_platform.change_feed",
      };
      if (!DogStatsd.Configure(dogstatsdConfig)){
          throw new InvalidOperationException("Cannot initialize Dogstatsd. Set optionalExceptionHandler argument in the `Configure` method for more information.");
      }

      // pass in the UUID so we can have multiple rollup processors running at the same time
      program.customerMonthlyUsageRollupProcessor = new CustomerMonthlyUsageRollupProcessor(program.instanceUUID, leaseContainer, monitoredContainer, monthlyCustomerRollupContainer, logger);
      await program.customerMonthlyUsageRollupProcessor.StartAsync();

      logger.LogInformation("Waiting on terminate, started CustomerMonthlyUsageRollupProcessor with {bp.changefeed.instanceUUID}", program.instanceUUID);

      ChangeFeedEstimator changeFeedEstimator = monitoredContainer.GetChangeFeedEstimator(program.customerMonthlyUsageRollupProcessor.ProcessorName, leaseContainer);
      if (changeFeedEstimator == null)
      {
          logger.LogError("Unable to create ChangeFeedEstimator");
          throw new InvalidOperationException("Unable to create ChangeFeedEstimator");
      }

      // Run the changefeed estimator indefinitely to monitor the lag every minute
      while (true)
      {
          try
          {
              using FeedIterator<ChangeFeedProcessorState> estimatorIterator = changeFeedEstimator.GetCurrentStateIterator();
              while (estimatorIterator.HasMoreResults)
              {
                  FeedResponse<ChangeFeedProcessorState> states = await estimatorIterator.ReadNextAsync();
                  foreach (ChangeFeedProcessorState leaseState in states)
                  {
                      DogStatsd.Counter("estimator_lag", leaseState.EstimatedLag, tags: [$"least_token:{leaseState.LeaseToken}"]);
                      logger.LogInformation("ChangeFeedEstimator state {bp.changefeed.estimated_lag} {bp.changefeed.lease_token} {bp.changefeed.instanceUUID} {bp.changefeed.instanceName}", leaseState.EstimatedLag, leaseState.LeaseToken, program.instanceUUID, leaseState.InstanceName);
                  }
              }
          }
          catch (Exception e)
          {
              logger.LogError(e, "Unable to retrieve change feed estimator status");
              DogStatsd.Increment("estimator_error");
          }

          // Sleep for 1 minute
          Thread.Sleep(60000);
      }
    }
    catch (Exception e)
    {
      logger.LogError(e, "An error occurred while running the console app. Exiting with code 1.");
      program.dirtyExit = true;
    }
    finally {
      logger.LogInformation("Exiting the console app!");
      loggerFactory.Dispose();

      if (program.customerMonthlyUsageRollupProcessor != null)
      {
          await program.customerMonthlyUsageRollupProcessor.StopAsync();
      }

      // Clean up the readiness probe file
      File.Delete("/tmp/console-running");

      if (program.dirtyExit)
      {
        Environment.Exit(1);
      }
    }
  }

  public static (string accountEndpoint, string accountKey) GetElementsFromConnectionString(string connectionString)
  {
    if (string.IsNullOrEmpty(connectionString))
    {
      throw new ArgumentException("Connection string is null or empty.");
    }
    var elements = connectionString.Split(';');
    var accountEndpoint = elements[0].Split("AccountEndpoint=")[1];
    var accountKey = elements[1].Split("AccountKey=")[1];

    return (accountEndpoint, accountKey);
  }
}
