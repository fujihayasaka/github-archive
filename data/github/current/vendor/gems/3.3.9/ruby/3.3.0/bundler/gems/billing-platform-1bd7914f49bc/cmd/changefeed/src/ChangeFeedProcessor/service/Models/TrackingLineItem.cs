namespace BillingPlatform.ChangeFeedProcessor.Models;

public class TrackingLineItem
{
    public string id { get; set; } = string.Empty;
    public string partitionKey { get; set; } = string.Empty;
    public string instanceUUID { get; set; } = string.Empty;
}
