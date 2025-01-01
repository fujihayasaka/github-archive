# Dynamic Workflows 
## What are they?
For an overview of dynamic workflows, visit: https://thehub.github.com/epd/engineering/products-and-services/actions/dynamic-workflows/

## How do I test a dynamic workflow locally (in a codespace)?
There is [this handy script](https://github.com/github/github/blob/master/script/actions/queue-codespaces-dynamic-run.rb) to test dynamic workflows in the `github` repository. 

The steps to test are: 
1. From `github`, run `script/server`
2. From `github`, run `start-actions`
3. Enable actions on a repository, eg `github/private-server`
4. Create a PR and note the sha 
5. Run the script from the root of `github` using the repository name and sha. 

For example:
```
script/actions/queue-codespaces-dynamic-run.rb --nwo github/private-server --ref d91a71c047793598c3bd4e75e730c8c84b085ac2
```
6. Expect a confirmation response in the console (no error)
7. Expect the workflow run to show in the actions tab of your repository 

## How do I test a dynamic workflow in lab?
Since all dynamic workflow requests are directed to the [production twirp client](https://github.com/github/github/blob/c0628fec11ccc325377dd8c1477b08e3a2034fad/packages/actions/app/models/repository/actions_dependency.rb#L162-L166), we use the production console to send a request directly to the launch lab client.

The steps to test are:
1. Log into the production console
2. Identify a repository you want to use to test
3. Create and run a workflow in `.github/workflows-lab` to create the launch lab installation
4. Set up the required parameters and send the request

For example:
```rb
repo = dat("YOUR_REPO_NAME_AND_OWNER")

actor = dat("USERNAME")

owner = repo.owner

installation = GitHub.launch_lab_github_app.installations_on(owner).with_repository(repo).first

workflow = %{
name: Integration Test

on: dynamic

jobs:
  build:
    runs-on: [ ubuntu-latest ]

    steps:
      - run: echo "Hello world"
}

Launch::Twirp.deployer_lab_client.run_dynamic_workflow(
  repository: repo,
  installation: installation,
  integration_name: "actions-lab",
  actor: actor,
  workflow: workflow,
  ref: "main",
  inputs: nil,
  workflow_name: "integration-test",
  slug: "integration-test",
  visibility: :DEFAULT,
  installation_valid_after: nil,
)
```