namespace BillingPlatform.ChangeFeedProcessor.Processors;

using Microsoft.Azure.Cosmos;
using StatsdClient;
using System.Collections.Concurrent;

using BillingPlatform.ChangeFeedProcessor.Models;
using Microsoft.Extensions.Logging;

public class CustomerMonthlyUsageRollupProcessor
{
    public static readonly string version = "v4";
    private static readonly object _lock = new object();
    private static readonly ConcurrentQueue<DateTime> TimestampQueue = new ConcurrentQueue<DateTime>();
    private static readonly int MAX_MSG_PER_SEC = 75;

    private ChangeFeedProcessor rollupProcessor;
    private Container rollupContainer;
    private ILogger logger;
    private Guid instanceUUID;
    private const int MAX_RETRIES = 10;
    public string ProcessorName = $"customer-monthly-usage-rollup-processor-{version}";

    public CustomerMonthlyUsageRollupProcessor(Guid instanceUUID, Container leaseContainer, Container monitoredContainer, Container rollupContainer, ILogger logger)
    {
        this.instanceUUID = instanceUUID;
        this.rollupProcessor = monitoredContainer
            .GetChangeFeedProcessorBuilder<LineItem>(ProcessorName, HandleChanges)
            .WithInstanceName($"customerMonthlyUsageRollupProcessor-{instanceUUID}")
            .WithLeaseContainer(leaseContainer)
            .WithLeaseAcquireNotification(OnLeaseAcquiredAsync)
            .WithLeaseReleaseNotification(OnLeaseReleaseAsync)
            .WithErrorNotification(OnErrorAsync)
            .WithStartTime(DateTime.UtcNow.AddMinutes(-10))
            .Build();

        this.rollupContainer = rollupContainer;
        this.logger = logger;
    }

    public async Task StartAsync()
    {
        logger.LogInformation("Starting CustomerMonthlyUsageRollupProcessor with {bp.changefeed.instanceUUID}", instanceUUID);
        await rollupProcessor.StartAsync();
    }

    public async Task StopAsync()
    {
        logger.LogInformation("Stopping CustomerMonthlyUsageRollupProcessor with {bp.changefeed.instanceUUID}", instanceUUID);
        await rollupProcessor.StopAsync();
    }

    private async Task HandleChanges(ChangeFeedProcessorContext context, IReadOnlyCollection<LineItem> changes, CancellationToken cancellationToken)
    {
        var leaseToken = context.LeaseToken;

        // Filter out changes that are not billable line items and cannot be processed for rollups
        var filteredChanges = changes.Where(change => change.id == LineItem.LINE_ITEM_ID && change.CanProcessRollup()).ToList();

        try
        {
            foreach (var change in filteredChanges)
            {
                await EnforceRateLimit(change.Pricing.Sku);
                await Task.Run(async () => await ProcessChangeAsync(change, leaseToken), cancellationToken);
            }
        }
        catch (Exception ex) when (ex is TaskCanceledException)
        {
            DogStatsd.Increment("task_cancelled");
        }
        catch (Exception ex)
        {
            DogStatsd.Increment("unhandled_processor_error", tags: [$"exception:{ex.GetType().Name}"]);
            logger.LogError(ex, "Unhandled exception in CustomerMonthlyUsageRollupProcessor {bp.changefeed.lease_token}", leaseToken);
        }
    }

    private async Task ProcessChangeAsync(LineItem change, string leaseToken) {
        var watch = System.Diagnostics.Stopwatch.StartNew();

        // Create a tracking line item to ensure we don't doubly process a change
        if (!await CreateTrackingLineItem(change, leaseToken))
        {
            logger.LogInformation("Skipping change {bp.change.id} {bp.change.pk} {bp.changefeed.lease_token} as it has already been processed", change.id, change.partitionKey, leaseToken);
            return;
        }

        logger.LogInformation("Processing change {bp.change.id} {bp.change.pk} {bp.changefeed.lease_token}", change.id, change.partitionKey, leaseToken);

        try
        {
            await RollupCustomerPartition(change);
        }
        catch (Exception ex)
        {
            DogStatsd.Increment("rollup_error", tags: [$"sku:{change.Pricing.Sku}", $"exception:{ex.GetType().Name}"]);
            logger.LogError(ex, "Error processing rollup for {bp.change.id} {bp.change.pk} {bp.changefeed.lease_token}", change.id, change.partitionKey, leaseToken);

            // TODO: Retry writing this rollup item

            return;
        }

        // This measures the time between the timestamp of the message and the time it was processed
        // This will give us a measure of how late we're in processing the message
        DogStatsd.Timer("changefeed_usage_at_lag", DateTime.Now.Subtract(UnixTimeStampToDateTime(change.UsageAt)).Duration().TotalSeconds, tags: [$"sku:{change.Pricing.Sku}"]);
        DogStatsd.Increment("customer_usage_rollup", tags: [$"processorUUID:{instanceUUID}", $"sku:{change.Pricing.Sku}"]);
        logger.LogInformation("Finished processing {bp.change.id} {bp.change.pk} {bp.change.elapsedTime} {bp.changefeed.lease_token}", change.id, change.partitionKey, watch.ElapsedMilliseconds, leaseToken);
    }

    /// <summary>
    ///  Enforces a rate limit according to the MAX_MSG_PER_SEC constant by
    ///  maintaining a queue of timestamps as we process changes.
    ///
    /// Timestamps older than 1 second are removed, if the remaining timestamps
    /// exceed the MAX_MSG_PER_SEC, we sleep until the oldest timestamp is at least 1 second old.
    /// </summary>
    /// <returns></returns>
    private async Task EnforceRateLimit(string sku) {
        lock (_lock)
        {
            DateTime now = DateTime.UtcNow;

            // Remove timestamps that are older than 1 second to enforce the rate limit at a per second rate
            while (TimestampQueue.TryPeek(out DateTime timestamp) && now.Subtract(timestamp).TotalSeconds > 1)
            {
                TimestampQueue.TryDequeue(out _);
            }

            if (TimestampQueue.Count >= MAX_MSG_PER_SEC)
            {
                DateTime oldestTimestamp = TimestampQueue.First();

                // calculate the delay to enforce the rate limit in milliseconds
                double millisecondDelay = 1000 - now.Subtract(oldestTimestamp).TotalMilliseconds;
                if (millisecondDelay > 0)
                {
                    // Ensure we don't sleep for more than 1 second
                    if (millisecondDelay > 1000)
                    {
                        millisecondDelay = 1000;
                    }

                    DogStatsd.Timer("rate_limit_delay", millisecondDelay, tags: [$"processorUUID:{instanceUUID}", $"sku:{sku}"]);
                    Thread.Sleep((int)millisecondDelay);
                }

                // Remove the timestamp we just delayed for
                TimestampQueue.TryDequeue(out _);
            }

            // Add the current timestamp to the queue
            TimestampQueue.Enqueue(DateTime.UtcNow);
        }

        await Task.CompletedTask;

        return;
    }

    /// <summary>
    ///  Creates a tracking line item for the given line item change to ensure we don't doubly process a change
    ///  This is necessary because the changefeed has an at-least-once delivery mechanism
    /// </summary>
    /// <param name="change"></param>
    /// <returns>Boolean indicating if the tracking line item has been successfully created or not</returns>
    private async Task<bool> CreateTrackingLineItem(LineItem change, string leaseToken) {
         var trackingLineItem = new TrackingLineItem{
            id = change.id,
            partitionKey = $"{change.partitionKey}:customerMonthlyUsageRollup",
            instanceUUID = instanceUUID.ToString()
        };

        try
        {
            await rollupContainer.CreateItemAsync(trackingLineItem, new PartitionKey(trackingLineItem.partitionKey));

            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Conflict)
        {
            DogStatsd.Increment("tracking_line_item_conflict", tags: [$"sku:{change.Pricing.Sku}"]);

            // change has already been processed
            return false;
        }
        catch (Exception ex)
        {
            DogStatsd.Increment("create_tracking_line_item_error", tags: [$"sku:{change.Pricing.Sku}", $"exception:{ex.GetType().Name}"]);
            logger.LogError(ex, "Error creating tracking item for {bp.change.id} {bp.change.pk} {bp.changefeed.lease_token}", change.id, change.partitionKey, leaseToken);

            return false;
        }
    }

    private async Task RollupCustomerPartition(LineItem lineItemChange, DiscountLineItem? discountItem = null) {
        var customerId = lineItemChange.EntityDetail.CustomerId;
        var sku = lineItemChange.Pricing.Sku;
        var date = UnixTimeStampToDateTime(lineItemChange.UsageAt);

        await RollupLineItem(
            lineItemChange,
            string.Format("{0}:{1}:{2}:{3}:{4}", customerId, sku, date.Year, date.Month, date.Day),
            string.Format("{0}:{1}:{2}", customerId, date.Year, date.Month)
        );
    }

    private async Task RollupLineItem(LineItem change, string id, string partitionKey) {
        var rollupItem = new LineItem {
            id = id,
            partitionKey = partitionKey,
            SourceUri = change.SourceUri,
            UsageAt = change.UsageAt,
            BilledAmount = change.BilledAmount,
            FullQuantity = change.FullQuantity,
            Quantity = change.Quantity,
            AppliedCostPerQuantity = change.AppliedCostPerQuantity,
            FractionalQuantity = change.FractionalQuantity,
            EntityDetail = change.EntityDetail,
            Pricing = change.Pricing
        };

        var retryCount = 0;
        var exception = null as Exception;
        while (retryCount < MAX_RETRIES)
        {
            // Try to create the item, if it already exists, increment the values instead
            try
            {
                await rollupContainer.CreateItemAsync(rollupItem, new PartitionKey(partitionKey));
                return;
            }
            catch (CosmosException cosmosEx) when (cosmosEx.StatusCode == System.Net.HttpStatusCode.Conflict)
            {
                try {
                    await rollupContainer.PatchItemAsync<LineItem>(id, new PartitionKey(partitionKey), patchOperations: [
                        PatchOperation.Increment("/BilledAmount", rollupItem.BilledAmount),
                        PatchOperation.Increment("/Quantity", rollupItem.Quantity),
                        PatchOperation.Increment("/FullQuantity", rollupItem.FullQuantity),
                        PatchOperation.Increment("/FractionalQuantity", rollupItem.FractionalQuantity)
                    ]);
                    return;
                }
                catch (Exception ex)
                {
                    retryCount++;
                    exception = ex;
                    logger.LogError(ex, "Retrying rollup on patch exception {bp.retryCount} {bp.change.id} {bp.change.pk}", retryCount, change.id, change.partitionKey);

                    // sleep for half a second before retrying
                    Thread.Sleep(500);
                }
            }
            catch (Exception ex)
            {
                retryCount++;
                exception = ex;
                logger.LogError(ex, "Retrying rollup {bp.retryCount} {bp.change.id} {bp.change.pk}", retryCount, change.id, change.partitionKey);

                // sleep for half a second before retrying
                Thread.Sleep(500);
            }
        }

        // throw the exception if we've exhausted our retries and still failed
        if (exception != null)
        {
            throw exception;
        }
    }

    private DateTime UnixTimeStampToDateTime(long unixTimeStamp)
    {
        DateTime start = DateTimeOffset.FromUnixTimeMilliseconds(unixTimeStamp).DateTime;
        var startUtc = DateTime.SpecifyKind(start, DateTimeKind.Utc);
        return startUtc;
    }

    private Task OnLeaseAcquiredAsync(string leaseToken)
    {
        logger.LogInformation("Lease {bp.changefeed.lease_token} is acquired and will start processing", leaseToken);
        DogStatsd.Increment("lease_acquire", tags: [$"leaseToken:{leaseToken}"]);

        return Task.CompletedTask;
    }

    private Task OnLeaseReleaseAsync(string leaseToken)
    {
        logger.LogInformation("Lease {bp.changefeed.lease_token} is released and processing is stopped", leaseToken);
        DogStatsd.Increment("lease_release", tags: [$"leaseToken:{leaseToken}"]);

        return Task.CompletedTask;
    }

    // Register a handler for WithErrorNotification to be notified when the current host encounters an exception during processing
    private Task OnErrorAsync(string leaseToken, Exception exception)
    {
        if (exception is ChangeFeedProcessorUserException userException)
        {
            logger.LogError(userException, "Lease {bp.changefeed.leaseToken} processing failed with unhandled exception from user delegate", leaseToken);
        }
        else
        {
            logger.LogError(exception, "Lease {bp.changefeed.leaseToken} processing failed", leaseToken);
        }

        DogStatsd.Increment("lease_processing_error", tags: [$"leaseToken:{leaseToken}"]);

        return Task.CompletedTask;
    }
}
