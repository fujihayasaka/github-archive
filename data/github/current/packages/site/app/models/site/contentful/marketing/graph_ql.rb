# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        Client = T.let(
          Site::Contentful::GraphQL::ClientBuilder.new(space: :marketing).build,
          T.any(::GraphQL::Client, Site::Contentful::GraphQL::NullClient)
        )
      end
    end
  end
end
