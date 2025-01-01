# Test launch with hydro/kafka locally 
This documentation guides you to set up dev environment (bpdev or codespace) to run end-to-end test with dotcom, launch, and hydro (kakfa).

## What do I need
Clone the following repos in your local env
- [github](https://github.com/github/github)
- [launch](https://github.com/github/launch)
- [hydro-schemas](https://github.com/github/hydro-schemas)

## Architecture

Launch sends messages to hydro, which is a layer on top of Kafka. In codespaces and GHES, [kafka-lite](https://github.com/github/kafka-lite) runs instead of a real Kafka instance. The messages are sent in protobuf format, and are defined in the [hydro-schemas](https://github.com/github/hydro-schemas) repository.

If you want to act on these messages, you need to set up a consumer listening to the message. In `github/github` these are called stream processors. An example is [here](https://github.com/github/github/blob/master/script/actions-usage-relay).


## Setup:
### github/github

Make sure you have kafka-lite running in github with port 9092. This can be checked using:

`$ lsof -nP -i4TCP:9092`

### github/launch

By default `KAFKA_BROKERS` is set up with a useful value in codespaces, to talk to `kafka-lite` at `localhost:9092` when you run `script/server`

## Test 
### Is my kafka-lite receiving messages from launch?

There can be [various ways](https://thehub.github.com/engineering/products-and-services/internal/hydro/guides/querying-events/#command-line) to check if a message is received by kafka-lite. One way is to use kafkacat:
1. [install kafkacat](https://thehub.github.com/engineering/products-and-services/internal/hydro/resources/faq/#q-how-do-i-install-kafka-locally). In linux, `$apt install kafkacat`
2. (optional) test the connection
- run `$kafkacat -C -b 127.0.0.1:9092 -b localhost:9092 -t cp1-iad.ingest.github.actions.v0.JobExecution` to watch kafka-lite
- queue a workflow to run, which should emit a JobExecution event
3. you should be able to see something shows up in the kafkacat watch terminal

## Useful resources
- [Kafka lite support docs for GHES](https://thehub.github.com/support/infrastructure/vendor-application-middleware/supporting-kafka-lite/#about-kafka-lite) can be useful even for local development (non-ghes), as local uses kafka lite too. 

## GHES
In GHES, we already have kafka publisher configured to send messages to kafka-lite. Therefore, launch needs to use kafka publisher instead of hydro client. Make sure that the consumer corresponding to the message you are testing is correctly configured.

[Kafka lite support docs for GHES](https://thehub.github.com/support/infrastructure/vendor-application-middleware/supporting-kafka-lite/#about-kafka-lite)

## Audit log specific

Check out this [audit log documentation](./audit-log.md)
