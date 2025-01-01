# Project Folder Structure

The main folders of the project are described here.

- `bin`: folder with executables built from `cmd`.
- `cmd`: all code that generates CLI executables lives here. It's here where the API server and various workers are declared.
- `config`: holds configuration files for deployment and services for kubernetes and moda.
- `coverage`: output of go testing coverage tool
- `docs`: internal documents for explaining the project and its architectural decisions.
- `generated`: Go Protobufs definitions.
- `internal`: Various internal go tools such as our feature flag client and our job scheduler
- `lib`: the majority of the code logic lives in this folder:
  - `azurecommerce`: base functions to work with Azure Commerce and PAv2.
  - `config`: application configuration
  - `db`: base functions to work with CosmosDB
  - `api`, `engines`, `models`: our Twirp endpoints defined in `api` create `engines` with the request data, engines use `models` to manipulate data, save it to the CosmosDB and return the result back to the API endpoint
  - `feature_flags`: feature flags client
  - `httpserver`: http server we use to run our Twirp APIs on
  - `hydro`: Hydro publisher to send events, like budget threshold notifications
  - `messaging`: message handlers to process items from Aqueduct
  - `rest`: utility functions to work with CosmosDB
  - `twirp`: Twirp server
  - `zuora`: Zuora emission logic and structs
- `proto`: definition for models and messages of the API.
- `ruby`: folder with the client API gem code.
- `script`: following the dotcom development philosophy, this folder holds all executable scripts.
- `testing`: test related code. Keep in mind that a lot of test files live side-by-side the real code in their respective folder.
- `ui`: React-based tool to test Twirp APIs
