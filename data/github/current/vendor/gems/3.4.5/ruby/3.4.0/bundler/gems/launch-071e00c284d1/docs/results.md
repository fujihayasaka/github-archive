# Actions Results

Launch sends postbacks to [actions-results](https://github.com/github/actions-results) via an aqueduct queue as part of the architecture for the [c2c-four-nines](https://github.com/github/c2c-four-nines) effort.

## Exporting Events

Proto contracts for actions-results are in the `pkg/results` folder in Launch.

To generate new protos:
1. In the [actions-results](https://github.com/github/actions-results) repo run `script/generate-proto --external --go-prefix github.com/github/launch/pkg/`
2. Copy the `results` folder from the actions-results `tmp` folder to the launch `pkg` folder, excluding `services` folder since we don't use them

