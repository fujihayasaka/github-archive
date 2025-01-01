# Limiter Package

The `limiter` package provides adaptive rate limiting for resources with unknown rate limits. It dynamically adjusts wait times based on success/failure patterns.

## Features

- **Adaptive Rate Limiting**: Automatically adjusts wait times based on success/failure rates
- **Per-Resource Management**: Different resources can have different wait times and queues
- **Thread-Safe**: Uses global locking for all critical sections
- **Dynamic Wait Time Updates**: Pending requests are updated when wait times change

## API

### `DoWait(name string)`
Waits synchronously until it's time to attempt calling the named resource. Multiple concurrent calls for the same resource will be queued and executed with proper spacing.

### `ReportSuccess(name string)`
Record a successful call for the resource.

### `ReportFailure(name string)`
Record a failed / rate-limited call for the resource.

### `WithRetry(ctx, resource, retry, fn)`
Runs `fn` once or with rate limiting + retry/backoff (up to `MaxIterations`) for retryable `errors.LLMError`s.
See usage example further down in this document.

### `MaxIterations` constant
A constant (20) representing the recommended maximum number of retry attempts for client code.

## Behavior

### Request Queuing
- **Ordered execution**: Concurrent requests for the same resource are queued in order
- **Proper spacing**: Each request waits until `waitTime` after the previous request's scheduled time
- **Dynamic updates**: If wait time changes while requests are queued, all pending requests are rescheduled

### Wait Time Adjustment
- **Initial wait time**: 50ms
- **Minimum wait time**: 20ms  
- **Maximum wait time**: 5000ms

### Automatic Adjustments
- **Increase wait time**: If 10+ results exist and failure rate > 5%, multiply by 1.5
- **Decrease wait time**: If all 100 results are successes, divide by 1.1

## Usage Example

```go
// Typical usage pattern in LLM clients
func (c *Client) makeSomeCall() (string, error) {
    var err error
    var result string

    for i := range limiter.MaxIterations {
        // Wait for rate limit before making request
        limiter.DoWait(c.getResourceName())

        // Make your API call
        result, err = doHTTPRequest()
        
        if err != nil && isRetryableError(err) {
            // Report failure for rate limit adjustment
            limiter.ReportFailure(c.getResourceName())
            if i < limiter.MaxIterations-1 {
                continue // Retry on retryable errors
            }
            break // Last iteration, stop retrying
        }

        // Report success
        limiter.ReportSuccess(c.getResourceName())
        break
    }

    return result, err
}
```

### `WithRetry` helper
Runs a function with optional rate limiting + retry handling. If `retry` is false it just calls the function once (no waiting, no reporting). If `retry` is true it:

- Applies `DoWait(resourceName)` before each attempt (up to `MaxIterations`).
- Retries only when the function returns a retryable `errors.LLMError`.

### `WithRetry` example
```go
// Simple example that returns a string.
func fetchGreeting(ctx context.Context) (string, errors.LLMError) {
    return limiter.WithRetry(ctx, "greeting", true, func() (string, errors.LLMError) {
        msg, err := callRemoteGreetingAPI(ctx)
        if err != nil {
            if isTransient(err) { // classify as retryable
                return "", errors.NewRetryableError("transient failure", 100*time.Millisecond)
            }
            return "", errors.NewError(err.Error(), errors.ErrorTypeLogic)
        }
        return msg, nil
    })
}
```
