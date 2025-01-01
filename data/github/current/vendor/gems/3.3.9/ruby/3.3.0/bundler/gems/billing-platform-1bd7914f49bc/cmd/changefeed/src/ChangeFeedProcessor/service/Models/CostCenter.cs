namespace BillingPlatform.ChangeFeedProcessor.Models;

public class CostCenter {
    public string EnterpriseCustomerId { get; set; } = string.Empty;
    public string CostCenterUUID { get; set; } = string.Empty;
    public string IsCostCenterProxy { get; set; } = string.Empty;

    public override string ToString()
    {
        return string.Format(
            "EnterpriseCustomerId: {0}, CostCenterUUID: {1}, IsCostCenterProxy: {2}",
            EnterpriseCustomerId, CostCenterUUID, IsCostCenterProxy
        );
    }
}
