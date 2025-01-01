namespace BillingPlatform.ChangeFeedProcessor.Models;

public class DiscountLineItem
{
    public string id { get; set; } = string.Empty;
    public string partitionKey { get; set; } = string.Empty;
    public long DiscountAmount { get; set; } = 0;
    public long Quantity { get; set; } = 0;
    public long UsageAt { get; set; } = 0;

    public Pricing Pricing { get; set; } = new Pricing();

    public override string ToString()
    {
        return string.Format("id: {0}, partitionKey: {1}, discountAmount: {2}", id, partitionKey, DiscountAmount);
    }
}
