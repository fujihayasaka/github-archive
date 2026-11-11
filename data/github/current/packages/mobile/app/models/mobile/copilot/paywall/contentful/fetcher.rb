# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      module Contentful
        class Fetcher
          PAYWALL_CONTENT_TYPE = "containerPage"
          PLANS_PAGE_SLUG = "/features/copilot/plans"
          # Maximum depth for resolving linked entries in Contentful
          MAX_INCLUDE_DEPTH = T.let(10, Integer)

          sig { returns(T.nilable(T::Hash[String, T.untyped])) }
          def self.fetch
            entries = Client.request(
              content_type: PAYWALL_CONTENT_TYPE,
              "fields.path": PLANS_PAGE_SLUG,
              include: MAX_INCLUDE_DEPTH
            )

            return nil if entries.nil? || entries.empty?

            entry = entries.first
            return nil if entry.nil?

            entry_to_hash(entry)
          end

          sig { params(entry: ::Contentful::Entry).returns(T::Hash[String, T.untyped]) }
          private_class_method def self.entry_to_hash(entry)
            result = {}
            entry.fields.each do |field_name, value|
              result[field_name.to_s] = convert_value(value)
            end
            result
          end

          sig { params(value: T.untyped).returns(T.untyped) }
          private_class_method def self.convert_value(value)
            case value
            when ::Contentful::Entry
              entry_to_hash(value)
            when ::Contentful::Asset
              asset_to_hash(value)
            when Array
              value.map { |v| convert_value(v) }
            else
              value
            end
          end

          sig { params(asset: ::Contentful::Asset).returns(T::Hash[String, T.untyped]) }
          private_class_method def self.asset_to_hash(asset)
            {
              "title" => asset.title,
              "url" => asset.url
            }
          end
        end
      end
    end
  end
end
