# typed: true
# frozen_string_literal: true

# Add @shareable federation directive to the built-in PageInfo type.
# PageInfo is defined by graphql-ruby and doesn't inherit from Platform::Objects::Base,
# so we include ApolloFederation::Object and declare @shareable explicitly here.
#
# This is placed in an initializer (rather than inline in a class body) to ensure
# it runs exactly once, avoiding duplicate directives during dev reloading.

Rails.application.config.after_initialize do
  unless GraphQL::Types::Relay::PageInfo.ancestors.include?(ApolloFederation::Object)
    GraphQL::Types::Relay::PageInfo.include(ApolloFederation::Object)
  end

  federation_aware = T.unsafe(GraphQL::Types::Relay::PageInfo)
  unless federation_aware.respond_to?(:own_federation_directives) &&
      federation_aware.own_federation_directives.any? { |d| d[:name] == "shareable" }
    federation_aware.shareable
  end
end
