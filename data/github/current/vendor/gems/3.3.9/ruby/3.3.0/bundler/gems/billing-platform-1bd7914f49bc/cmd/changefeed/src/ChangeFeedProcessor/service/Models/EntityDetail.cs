namespace BillingPlatform.ChangeFeedProcessor.Models;

public class EntityDetail {
    public string CustomerId { get; set; } = string.Empty;
    public long OrganizationId { get; set; } = 0;
    public long RepositoryId { get; set; } = 0;
    public long ActorId { get; set; } = 0;

    public CostCenter CostCenterDetail { get; set; } = new CostCenter();

    public override string ToString()
    {
        return string.Format(
            "CustomerId: {0}, OrganizationId: {1}. RepositoryId: {2}, ActorId: {3}, CostCenter: {4}",
            CustomerId, OrganizationId, RepositoryId, ActorId, CostCenterDetail.ToString()
        );
    }
}
