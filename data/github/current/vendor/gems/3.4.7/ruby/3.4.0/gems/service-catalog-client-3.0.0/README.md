# ServiceCatalog::Client

A Ruby client for GitHub's Service Catalog.

## Installation

The Ruby client is published to [GitHub Packages](https://github.com/orgs/github/packages?repo_name=cat) and Octofactory.

GitHub Packages is the easiest way to get the gem. It works on Codespaces and locally without needing the GitHub VPN. Add the following to your Gemfile, then `bundle` as usual.

```ruby
source "https://rubygems.pkg.github.com/github" do
  gem "service-catalog-client"
end
```
## Usage

All use of the client is via the `ServiceCatalog::Client` instance:

```ruby
require "service-catalog-client"

# Create a client with your API token.
client = ServiceCatalog::Client.new(
    endpoint: "https://catalog.githubapp.com/graphql",
    token: ENV["SERVICE_CATALOG_TOKEN"],
    tracer: GitHub::Telemetry.tracer, # Optional tracer! Must respond to `#in_span(name, attributes:)`.
)

# List services which have a maintainer.
# Documentation for this query can be found at
# https://catalog.githubapp.com/docs/ServiceCatalog/Client/ServicesQueryBinder.html#list-instance_method
response = client.services.list(query: "maintainer.active:true", ...)
response.data.services.each do |service|
  puts "Fetched #{service.name}"
end
```

## Instrumentation

Using `ActiveSupport::Notifications`, we instrument queries as well as first-party loaders like `#services`. Each instrumentation key is specified in the query module, so if you want to instrument listing of services, you'd subscribe like this:

```ruby
ActiveSupport::Notifications.subscribe(ServiceCatalog::Client::Services::ListServicesQuery::INSTRUMENTATION_KEY) do |name, start, finish, id, payload|
    # Do something with the data. Payload differs per event.
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

You can start developing and testing with [your personal API token](https://github.com/github/cat/blob/HEAD/docs/api.md#how-to-get-an-api-token). When you'd like a long-lived bot token for your service, please [open an issue requesting one](https://github.com/github/cat/issues/new).

## Releasing

To release, make sure `CHANGELOG.md` is updated and accurate. Also, the version in `lib/service-catalog/client/version.rb` must get bumped. After bumping the client version, run the following in the root of the project to update the client version in `Gemfile.lock`:

```
$ bundle install
```

A tag with the version as the name should get created. Use the appropriate notes from `CHANGELOG.md` as the message for the tag. Here is an example showing how to create a tag:

```
# The command below will sign the tag and open an editor to populate the message for the tag.
# The message will also get used as the notes for the GitHub release.
$ git tag -s service-catalog-client/v1.1.0
$ git push --tags
```

Once the tag is pushed, a release process will begin using GitHub actions. It will create a release, upload the gem as a release asset and publish the gem to GitHub Packages. In addition to this process, every push to `main` will invoke the `cat-ruby-client-build-gem` build step which will publish the gem to [Octofactory](https://octofactory.githubapp.com/). More on that specific build process can be found on [TheHub](https://thehub.github.com/engineering/development-and-ops/ci/gem-template-build-pipelines/). The Octofactory version of the gem can be found in Octofactory [here](https://octofactory.githubapp.com/artifactory/list/github-gems/gems/). Because this gem gets published so frequently to Octofactory, it is preferred that the gem gets vendor'ed or the GitHub Packages version of the gem is used instead.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/github/cat. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is not open source at this time. All rights reserved, copyright GitHub, Inc. 2022.

## Code of Conduct

Everyone interacting in the ServiceCatalog::Client project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/github/cat/blob/HEAD/service-catalog-client/CODE_OF_CONDUCT.md).
