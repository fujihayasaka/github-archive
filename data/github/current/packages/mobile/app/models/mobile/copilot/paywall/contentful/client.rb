# typed: strict
# frozen_string_literal: true

require "contentful"

module Mobile
  module Copilot
    module Paywall
      module Contentful
        class Client
          sig { returns(::Contentful::Client) }
          def self.client
            ::Contentful::Client.new(
              space: GitHub.contentful_marketing_space_id,
              access_token: GitHub.contentful_marketing_delivery_token,
              environment: GitHub.contentful_marketing_environment,
            )
          end

          sig { params(params: T::Hash[Symbol, T.anything]).returns(T.nilable(::Contentful::Array)) }
          def self.request(params)
            client.entries(params)
          rescue ::Contentful::Error => err
            GitHub.dogstats.increment(
              "copilot.paywall_contentful.failures",
              tags: ["method:contentful_request", "error:#{err.class}"]
            )

            raise if Rails.env.development?
            nil
          end
        end
      end
    end
  end
end
