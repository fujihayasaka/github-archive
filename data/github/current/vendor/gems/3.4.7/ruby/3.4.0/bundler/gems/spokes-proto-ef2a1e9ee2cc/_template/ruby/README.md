# Spokes Access API Ruby Client

This gem contains a Ruby client to interact with Spokes Access API. The entry point for using Spokes Access API from Ruby is `GitHub::Spokes::Proto::Client`. Its constructor takes a URL and several other options. See [`client.rb`](lib/github/spokes/proto/client.rb) for the list of options.

`GitHub::Spokes::Proto::Client` has attr accessors for each of the API clients. For example, `#commits` gets a Commits API client.

When making calls to Spokes Access API, clients will typically use a helper to create a repository object and pass the rest of the request body as a hash. For example:

```ruby
# Spokes Access API requests all include a repository argument. Use 'new_repository',
# 'new_gist', or 'new_wiki' to create the value for this argument.
repository = GitHub::Spokes::Proto::Types.new_repository(1)

# Build the request.
request = {
  repository: repository,
  by_id: {id: "8b00d48a83de48e54544be903c28d7aff32d7b25"},
}

# Make the request.
resp = client.blobs.get_blob_contents(request)

puts resp.data.contents
```

For a more complete example, see [`examples/ruby` in the spokes-api repository](https://github.com/github/spokes-api/tree/master/examples/ruby).
