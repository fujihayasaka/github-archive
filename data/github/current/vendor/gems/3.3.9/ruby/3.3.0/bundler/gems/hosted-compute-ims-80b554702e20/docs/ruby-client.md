# Dotcom client `hosted-compute-ims` gem

This client is to make it easier for the monolith to integrate with the IMS API. This a client wrapper for our Twirp APIs.

## Source

The source for the gem lives in the [`/gen/twirp/ruby`](../gen/twirp/ruby) directory in this repository.

> [!WARNING]  
> We specifically use an old version of Ruby Twirp code generator because dotcom doesn't support newer codegen yet.
> Here is an example of the error we faced due to the different protoc versions causing problems:
> ```
> Requiring all gems to prepare for compiling... 
>   Loading GitHub environment ... Ready!
> /workspaces/github/vendor/gems/3.3.0/ruby/3.3.0/gems/proto-registry-metadata-api-1.11.0.30.gd61a5519b/lib/proto/registrymetadata/container_entities.rb:13:in `<main>': undefined method `add_serialized_file' for an instance of Google::Protobuf::DescriptorPool (NoMethodError)
> ```

## Updating the gem in the Dotcom

To vendor a new IMS gem into `github/github` use the following steps:
1. Update gem:
  - Get the latest commit SHA from IMS repo.
  - Update `Gemfile` in gh/gh.
    ```
    gem "hosted-compute-ims", github: "github/hosted-compute-ims", glob: "gen/twirp/ruby/*.gemspec", ref: "<commit SHA from ims repo>"
    ```
  - Run `bin/bundle`
2. Regenerate sorbet files for gem:
  - `bin/tapioca gem  hosted-compute-ims`
  - `bin/tapioca dsl`

Also, consider updating IMS client in dotcom to add new methods / change existing ones: [gitub/lib/hosted_compute_ims/twirp](https://github.com/github/github/tree/master/lib/hosted_compute_ims/twirp)

Once you've updated the gem, just open and deploy a github/github PR as normal.
