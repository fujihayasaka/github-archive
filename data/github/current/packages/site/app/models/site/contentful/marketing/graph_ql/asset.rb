# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        class Asset
          Fragment = Site::Contentful::Marketing::GraphQL::Client.parse <<-'GRAPHQL'
            fragment on Asset {
              __typename
              sys {
                id
              }
              contentType
              description
              height
              url
              width
            }
          GRAPHQL
        end
      end
    end
  end
end
