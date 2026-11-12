# Turbocassette

Turbocassette provides Ruby and Go tooling to support Contract Testing at GitHub.

Turbocassette implements consumer-driven contracts based on a *record-replay-regenerate* approach to creating, verifying, and maintaining contracts.

* Record: Contracts are creating by recording the network interaction between the client/consumer and the server/provider. This is done via extensions of the VCR library.
* Replay: Contract verification is done by writing tests on both the consumer and provider that replay the VCR and fail if braking changes are detected.
* Regenerate: Contracts are re-generated every time the provider changes its observable behavior.

## Getting Started

TBD: Link to Turboscan usage of turbocassette in gh/gh and gh/turboscan.

## Known Limitations

- The Go VCR library currently does not support custom matchers. This was a deliberate design choice, as we are looking into whether to integrate a matcher approach based on JSONPath (like Pact does). Extending the library is relatively simple, so if this is blocking we can probably prioritize this.
- The Ruby library only provides the consumer scaffolding. There is no support for provider verification and cassette re-generation. This is mostly for historical reasons, but something we need to address.
- The contract format is currently directly using Ruby's VCR format. We are exploring using the Pact contract format or an extension of it. Thus, you should not assume the contract format to stay stable for now. Any big change in contract format will come with some tooling to help the transition.



## Out of scope (Non-Goals)

When testing the integration of services, we can work at various levels. For example, we can replace the provider with a mock service and test the consumer by exercising the TCP/IP connection to the mock service. This is sometimes called a *test double*. A good library to work with test doubles is [Mountebank](https://www.mbtest.org/).

Test doubles treat the consumer/provider as a black boxes. This has a few benefits:
* No need to modify the code of the consumer/provider: it works even if the code is not available.
* The same implementation supports any language, as long as the underlying protocol is supported. In the case of Mountebank the protocol is TCP/IP, but other solutions might only support HTTP.
* The test double can be used during development of the consumer, avoiding the expensive setup of the provider.

The main drawbacks of the approach are:
* The provider might not expose enough functionality to set it up into a given configuration. A typical example are error states: it might be impossible to work on a contract that requires an error state of the provider.
* Slow to run tests as we need to setup, configure, and eventually teardown the test double.

By relying on VCR, Turbocassette works at a lower level and treats both the consumer and provider as grey-boxes. We still recognize that the black-box/test double approach has its merits, especially when considering test doubles for development. However, this is strictly out-of-scope for turbocassette.

We hope other efforts will explore test doubles, and it would be ideal if those efforts could re-use the Turbocassette's contract format (or an extension thereof).

## How is this different from Pact?

[Pact](https://docs.pact.io/) is a well-established tool set for consumer-driven contract testing.
The main reason we believe Pact does not meet our needs[^1] is that Pact is *code-first* consumer-driven.

Code-first means that the contract is defined by the consumer in its test by explicitly defining the provider response as a mock expectation. This approach works fine if we are unit-testing the consumer methods. However, it becomes quite cumbersome if we are testing larger integrations that might (for example) require multiple interactions between the consumer and provider, or if we are not familiar with the details of the provider response.

The suggested work around from Pact for this problem is to focus the mock only on the response fields that are actually necessary. While this does simplify the task, it still requires quite a bit of knowledge of the internals of the systems under tests: changes to those internals might require changes to the tests.

We believe *recording* the consumer-provider interactions is a better approach for doing contract testing in existing projects, while requiring a low-level of understanding on the system internals.
Pact remains a valid tool to consider when doing a greenfield project, and when the consumer can drive the design of the provider.



[^1]: For a more in-depth discussion see this [Video](https://github.rewatch.com/video/s3i2ccw4vedx04w8-contract-testing-with-pact) and/or [Slides](https://docs.google.com/presentation/d/1aocPKCsbPgfePIusTbRAs_ewZOEwOCo8UJLCiE7t_Ck/edit#slide=id.p)