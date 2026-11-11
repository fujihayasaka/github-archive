# Testing Twirp Changes in a Codespace

If you need to make some changes to the twirp API and want to test them with dotcom without having to publish the gem and publish to octofactory, follow the steps below:

From sweagentd root:
```
make proto

mkdir -p tmp/monolith-twirp-sweagentd-sweagentd

docker run -e NAMESPACE=sweagentd \
  -e MODULE_ROOT=proto \
  -e NWO=github/sweagentd \
  --volume $(pwd):/repo \
  --volume $(pwd)/tmp/monolith-twirp-sweagentd-sweagentd:/docker-build-artifacts \
  ghcr.io/github/monolith-twirp-tools/gen-ruby:latest generate

 cp ./tmp/monolith-twirp-sweagentd-sweagentd/gems/monolith-twirp-sweagentd-sweagentd-1.1.4.gem /workspaces/github/vendor/cache/
```

Update `Gemfile` and `Gemfile.lock` in `github/github` (needs both) to use the new version, then run `script/bootstrap --local`

Then start the server as you usually would
