# How to Update Hydro Schemas

Message schemas for Hydro (Kafka) are maintained externally in the [hydro-schemas](https://github.com/github/hydro-schemas) repository. Billing Platform protobuf generations are located in the directory [proto/hydro/schemas/billingplatform](https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/billingplatform). This contains a folder for both [v0](https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/billingplatform/v0) (meuse) and [v1](https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/billingplatform/v1) (billing platform).

## Table of Contents

- [Terminology](#terminology)
- [How to generate hydro schema protobufs](#how-to-generate-hydro-schema-protobufs)
- [References](#references)

## Terminology

- **Hydro schema**: The definition of the protobuf data that will be sent over Hydro.
- **Protobuf**: A Protobuf, or protocol buffer, is a specification for sending data between API methods.

## How to generate hydro schema protobufs

In order to generate new protobuf files in Billing Platform if you make changes to any definitions in the `hydro-schemas` repository, these are the steps:

1. Clone the [hydro-schemas](https://github.com/github/hydro-schemas) repo to your codespace - this should be the same level as the `billing-platform` repo, in the `/workspaces` folder.
2. Navigate to the that repo.
3. Run the following command, replacing `<schema-file-you-want-to-sync>` with the hydro schema file you want to generate the protobuf for. Eg: `./proto/hydro/schemas/billingplatform/v1/usage_line_item.proto`:

    ```bash
    ./script/generate <schema-file-you-want-to-sync> --go-out "../billing-platform/generated" --go-prefix "github.com/github/billing-platform/generated"
    ```

    Alternatively, there is a script that can be used to run this step located [here](https://github.com/github/billing-platform/blob/main/script/make-hydro-schema-protos). Example usage of this script is `script/make-hydro-schema-protos billingplatform/v1/usage_line_item.proto`

4. Open the `billing-platform` repo in your codespace. The protobuf changes should be visible in the `generated/hydro/schemas/billingplatform/v1` folder.

> [!IMPORTANT]
> Using this tooling can change the `package` name in the protobuf file. This seems to be related to the protoc version that gets used in the `script/generate` command mentioned above. If this changes for you, you should manually revert it as a workaround. The correct package to use for `billing-plaform` is `hydro_schemas_billingplatform_v1`.

## References

- [The Hub doc on Hydro](https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/)
- [Protocol Buffers](https://protobuf.dev/)
