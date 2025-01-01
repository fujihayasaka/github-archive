# How to run Vexi Demo's

## File Adapter Demo
Run `make demo`
## Feature Flag Hub Adapter Demo

The following are the steps specific to setting up 2 codespaces for running the demo for the feature flag hub adapter.

### Steps
- Update `gh CLI` to latest on your host PC
- Clone github/feature-management and run `./script/e2e-test-vexi-ruby --create` : this will create the codespaces you will need to run the demo
- In `Codespace FFH`, run `script/setup -i` to initialize the emulator
- In `Codespace FFH`, run `script/server`
- On `Codespace FMCR` run `make demo-hub-adapter`

If you want to set up your codespaces manually.

- Create a Codespace in Feature Management Client for Ruby. We'll call this `Codespace FMCR`
- Create a Codespace in the Feature Flag Hub. We'll call this `Codespace FFH`
- Run the server on `Codespace FFH`. The port it is forwarding to the host PC is 8090. This can be seen in the Ports tab of vscode and is the port you use to access the server that is running on that Codespace on your host PC.
- In a terminal on the host run `gh codespace ssh -- -R 8090:127.0.0.1:8090` and then pick `Codespace FMCR` from the list of Codespaces that shows up when prompted. Once the ssh session starts run `curl http://127.0.0.1:8090` to test that the `Codespace FMCR` can now hit the url for `Codespace FFH`
- In `Codespace FFH`, run `script/setup -i` to initialize the emulator
- In `Codespace FFH`, run `script/server`
- On `Codespace FMCR` run `make demo-hub-adapter`

Note:
`create_demo_examples` in the `demo_hub_adapter.rb` can be commented out once the feature flags and segments have been loaded to the FFH.