# Test Producer

Testing hydro locally requires Kafka-lite to be running. You can start it by
bringing up the Docker container with the following:

```bash
./script/bootstrap
```

Next you need to make the hydro-producer binary.

```bash
make hydro-producer

```

Now we're ready to send some Hydro messages!

## `MembershipUpdate`
  
```bash
./bin/hydro-producer --message-type MembershipUpdate --action ADD --context REPOSITORY
```

## `OrganizationAdd`

```bash
./bin/hydro-producer --message-type OrganizationAdd --organization-id 1
```
