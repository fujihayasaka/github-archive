# Protobuf definitions for Dependabot-as-server Twirp APIs

This folder contains protobuf contracts for Twirp APIs where dependabot-api is the server and external services (including github/github) are the clients.

## Making changes to Twirp APIs in this folder

When changes are made to the `proto/dependabot-api/` directory, the corresponding generated protobuf files and gems should be updated. This can be done by executing `script/protoc` from the project root.