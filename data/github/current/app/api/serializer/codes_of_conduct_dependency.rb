# typed: true
# frozen_string_literal: true

module Api::Serializer::CodesOfConductDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  def code_of_conduct_hash(code_of_conduct, options = {})
    return nil unless code_of_conduct
    options = Api::SerializerOptions.from(options)

    hash = {
      key: code_of_conduct.legacy_key,
      name: code_of_conduct.name,
      html_url: (code_of_conduct.url.to_s if code_of_conduct.url),
    }

    hash[:url] = if code_of_conduct.respond_to?(:repository)
      url("/repos/#{code_of_conduct.repository.name_with_owner_for_api(use: options[:serialize_login])}/community/code_of_conduct", options)
    else
      url("/codes_of_conduct/#{code_of_conduct.legacy_key}", options)
    end

    hash[:body] = code_of_conduct.body if options[:full]

    hash
  end

  PartialCodeOfConductFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on CodeOfConduct {
      key
      name
      url
      repository {
        nameWithOwner
      }
    }
  GRAPHQL

  FullCodeOfConductFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on CodeOfConduct {
      key
      name
      url
      repository {
        nameWithOwner
      }
      body
    }
  GRAPHQL

  def graphql_code_of_conduct_hash(code_of_conduct, options = {})
    options = Api::SerializerOptions.from(options)
    code_of_conduct = if options[:full]
      FullCodeOfConductFragment.new(code_of_conduct)
    else
      PartialCodeOfConductFragment.new(code_of_conduct)
    end

    hash = {
      key: code_of_conduct.key,
      name: code_of_conduct.name,
      html_url: (code_of_conduct.url.to_s if code_of_conduct.url),
    }

    hash[:url] = if code_of_conduct.repository
      # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
      url("/repos/#{code_of_conduct.repository.name_with_owner}/community/code_of_conduct", options) # rubocop:disable GitHub/DoNotAllowNameWithOwner
    else
      url("/codes_of_conduct/#{code_of_conduct.key}", options)
    end

    hash[:body] = code_of_conduct.body if options[:full]

    hash
  end
end
