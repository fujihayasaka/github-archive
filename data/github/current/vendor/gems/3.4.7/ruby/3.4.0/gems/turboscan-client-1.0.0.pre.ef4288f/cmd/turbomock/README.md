# Turbomock

This is a fake turboscansvc which will reply with canned responses.

## Usage

To modify the way Turbomock replies, edit the files within the `services/` folder.

To re-vendor Turbomock after a cassette or Twirp API change, update the gem as normal.

## Customizing Responses

There are two primary approaches to customize how Turbomock responds to requests:

### 1. Load different cassettes based on request parameters (recommended)

You can conditionally load different cassette files based on the request parameters. This allows you to simulate different scenarios without maintaining state.

Example from [`GetAlerts`](https://github.com/github/turboscan/blob/main/cmd/turbomock/root/services/results.go#L32):

```go
func (r *ResultsResponses) GetAlerts(ctx context.Context, req *proto.AlertsRequest) (resp *proto.AlertsResponse, err error) {
    if req.ResolvedOnly {
        return data.LoadCassette(ctx, "get-alerts-state-filter-closed.yml", resp)
    }
    if req.FilePaths != nil {
        return data.LoadCassette(ctx, "get-alerts-path-filter.yml", resp)
    }
    // ... other conditions
    return data.LoadCassette(ctx, "get-alerts-state-filter-open.yml", resp)
}
```

### 2. Maintain state in memory (be cautious)
For more complex scenarios where you need to maintain state between requests, you can use in-memory state to track changes.

Example from [`CreateAlertLinks`](https://github.com/github/turboscan/blob/main/cmd/turbomock/root/services/results.go#L243):

```go
func (r *ResultsResponses) CreateAlertLinks(ctx context.Context, req *proto.CreateAlertLinksRequest) (resp *proto.CreateAlertLinksResponse, err error) {
    for _, link := range req.Links {
        if link.PullRequestId != 0 {
            r.alertLinks.Pr = true
        }
        if len(link.RefNameBytes) > 0 {
            r.alertLinks.Branch = true
        }
    }
    return &proto.CreateAlertLinksResponse{}, nil
}
```

This state can then be used in other methods to provide consistent responses:

```go
func (r *ResultsResponses) GetLinksForAlerts(ctx context.Context, req *proto.GetLinksForAlertsRequest) (resp *proto.GetLinksForAlertsResponse, err error) {
    links := []*proto.AlertLink{}
    if r.alertLinks.Pr {
        // Return PR links when they exist in state
        links = append(links, &proto.AlertLink{
            AlertNumber:   req.ReposAndAlerts[0].Number,
            PullRequestId: 1,
            RepositoryId:  req.ReposAndAlerts[0].RepositoryId,
        })
    }
    // ...
}
```
