namespace BillingPlatform.ChangeFeedProcessor.Models;

public class LineItem
{
    public const string LINE_ITEM_ID = "billable";

    public string id { get; set; } = string.Empty;
    public string partitionKey { get; set; } = string.Empty;
    public string SourceUri { get; set; } = string.Empty;
    public long UsageAt { get; set; } = 0;
    public long BilledAmount { get; set; } = 0;
    public long FullQuantity { get; set; } = 0;
    public long Quantity { get; set; } = 0;
    public long AppliedCostPerQuantity { get; set; } = 0;
    public long FractionalQuantity { get; set; } = 0;

    public EntityDetail EntityDetail { get; set; } = new EntityDetail();
    public Pricing Pricing { get; set; } = new Pricing();

    public override string ToString()
    {
        return string.Format("id: {0}, partitionKey: {1}", id, partitionKey);
    }

    public bool IsWatermarkEvent()
    {
        return Pricing.MeterType == MeterTypeEnum.PerHour && this.SourceUri != "InternallyProcessedEvent";
    }

    public bool CanProcessRollup()
    {
        return !this.IsWatermarkEvent();
    }
}
