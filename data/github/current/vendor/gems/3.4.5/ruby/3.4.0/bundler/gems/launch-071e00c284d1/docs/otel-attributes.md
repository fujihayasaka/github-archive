## OTel attribute naming and registration guide

### Naming

OTel attributes must be string literals, meaning e.g. `kvp.String(attributeName [...])` is not OTel compliant.

OTel attributes must also be named in compliance with [Semantic Conventions](https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/opentelemetry-logging/#attribute-naming) when emitting traces and exceptions.
For more info on naming, see the [Semantic Conventions User Guide.](https://thehub.github.com/epd/engineering/dev-practicals/observability/semantic-conventions/user-guide/)

If the new OTel attribute exists outside of launch as well, it will likely be named something like `gh.complex_object_if_any.attribute_name`. E.g. `gh.repo.id`.

If the new OTel attribute only exists in launch, it will likely be named something like `gh.launch.[...]`. E.g `gh.launch.action_resolver_app.id`.

### Classification

Once named, the attribute must be evaluated from a privacy perspective and then classified as one of the following:
  - `NONE`: Does not contain any sensitive information and does not need to be redacted by the telemetry infrastructure
  - `CUSTOMER_CONTENT`: Contains customer content and still needs to be redacted by the telemetry infrastructure
  - `EUII`: Contains EUII and still needs to be redacted by the telemetry infrastructure
  - `EUPI`: Contains pseudonymized EUII but does not need to be redacted by the telemetry infrastructure

Refer to the [classification guide](https://github.com/github/privacy/wiki/Proxima:-Data-Classification-Guidance) for more elaborate advice on classification.

## Registration

Launch service attributes starting with `gh.*` must be registered in [gh-classifications.yaml](https://gh.io/gh-classifications) 

See the example below:

```yaml
trace:
- name: gh.launch.action_name
  classification: CUSTOMER_CONTENT
- name: gh.launch.action_name_version
  classification: CUSTOMER_CONTENT
- name: gh.launch.action_resolver_app.id
  classification: NONE
```

> **NOTE:** Upstream Semantic Convention based attributes that are emitted by the OTel SDK or automatic instrumentation are already registered for you! No need to register them again.
