using OpenTelemetry;
using OpenTelemetry.Logs;
using BillingPlatform.ChangeFeedProcessor.LogExporters;

internal static class LoggerExtentions
{
    public static OpenTelemetryLoggerOptions AddGHExporter(this OpenTelemetryLoggerOptions options)
    {
        if (options == null)
        {
            throw new ArgumentNullException(nameof(options));
        }

        return options.AddProcessor(new BatchLogRecordExportProcessor(new GHExporter()));
    }
}