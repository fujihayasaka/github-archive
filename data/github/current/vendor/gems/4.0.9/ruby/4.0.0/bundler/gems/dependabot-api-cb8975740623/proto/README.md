## Dependabot API Protobuf Definitions

This folder contains Protocol Buffer definitions we are responsible for maintaining. The workflows for maintaining the definitions differs significantly based on the directory.

### dependabot-api

This folder contains protobuf contracts for Twirp APIs where dependabot-api is the server and external services (including github/github) are the clients.

See [the folder's README](./dependabot-api/README.md) for more details

### monolith

This folder contains protobuf contracts for Twirp APIs where dependabot-api is the client and github/github is the server

See [the folder's README](./monolith/README.md) for more details