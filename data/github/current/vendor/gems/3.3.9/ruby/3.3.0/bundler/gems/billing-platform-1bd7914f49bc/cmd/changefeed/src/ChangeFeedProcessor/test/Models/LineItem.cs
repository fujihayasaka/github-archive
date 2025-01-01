namespace BillingPlatform.ChangeFeedProcessor.Processors.Tests;

using Xunit;

using BillingPlatform.ChangeFeedProcessor.Models;

public class LineItemTests
{
    [Fact]
    public Task Test_ToString()
    {
        var id = "billable";
        var partitionKey = "cfc2ea0f-07ae-4ea2-b98e-c6d36f53d433";

        var lineItem = new LineItem
        {
            id = id,
            partitionKey = partitionKey,
        };

        Assert.Equal(
            lineItem.ToString(),
            string.Format("id: {0}, partitionKey: {1}", id, partitionKey)
        );

        return Task.CompletedTask;
    }

    [Fact]
    public Task Test_LINE_ITEM_ID()
    {
        Assert.Equal(LineItem.LINE_ITEM_ID, "billable");

        return Task.CompletedTask;
    }
}
