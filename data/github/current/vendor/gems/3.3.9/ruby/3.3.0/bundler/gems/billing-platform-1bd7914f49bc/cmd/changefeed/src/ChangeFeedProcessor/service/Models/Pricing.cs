namespace BillingPlatform.ChangeFeedProcessor.Models;

public enum MeterTypeEnum
{
    Default = 0, // aka DirectSummation, aka actions minutes
    PerHour = 1,  // aka actions storage
    Daily = 2, // aka high watermark
}

public class Pricing {
    public string partitionKey { get; set; } = string.Empty;
    public string id { get; set; } = string.Empty;
    public long Price { get; set; } = 0;
    public string Product { get; set; } = string.Empty;
    public string Sku { get; set; } = string.Empty;
    public MeterTypeEnum MeterType { get; set; } = MeterTypeEnum.Default;
    public string FriendlyName { get; set; } = string.Empty;
    public string AzureMeterId { get; set; } = string.Empty;
    public bool FreeForPublicRepos { get; set; } = false;
    public long EffectiveAt { get; set; } = 0;
    public int UnitType { get; set; } = 0;

    public override string ToString()
    {
        return string.Format(
            "partitionKey: {0}, id: {1}. Price: {2}, Product: {3}, Sku: {4}",
            partitionKey, id, Price, Product, Sku
        );
    }
}
