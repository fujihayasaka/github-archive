namespace BillingPlatform.ChangeFeedProcessor.LogExporters;

using OpenTelemetry;
using OpenTelemetry.Logs;
using System.Text;
using System.Text.RegularExpressions;

class GHExporter: BaseExporter<LogRecord>
{
    public override ExportResult Export(in Batch<LogRecord> batch)
    {
        using var scope = SuppressInstrumentationScope.Begin();

        foreach (var record in batch){
            var sb = new StringBuilder();
            sb.Append($@"Body=""{record.Body}""").Append(' ');
            sb.Append($@"Timestamp=""{record.Timestamp}""").Append(' ');
            sb.Append($@"InstrumentationScope=""{record.CategoryName}""").Append(' ');

            if (record.Exception != null){
                var stackTraceString = Regex.Escape(record.Exception.StackTrace?.Trim() ?? "");

                sb.Append($@"exception.type=""{record.Exception.GetType().Name}""").Append(' ');
                sb.Append($@"exception.message=""{record.Exception.Message}""").Append(' ');
                sb.Append($@"exception.stacktrace=""{stackTraceString}""").Append(' ');
                sb.Append($@"SeverityText=""{record.LogLevel.ToString().ToUpper()}""").Append(' ');
            }
            // Log any extra attributes
            if (record.Attributes != null && record.Attributes.Count > 1)
            {
                foreach (var kvp in record.Attributes)
                {
                    // Skip OriginalFormat and Arguments because these is a duplicate of the message
                    if (kvp.Key == "{OriginalFormat}" || kvp.Key == "OriginalFormat" || kvp.Key == "Arguments")
                    {
                        continue;
                    }
                    sb.Append($@"{kvp.Key}=""{kvp.Value}""").Append(' ');
                }
            }

            // do not remove this line it is responsible for sending formatted logs to the STDOUT
            Console.WriteLine(sb.ToString());
        }

        return ExportResult.Success;
    }
}
