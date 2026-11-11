# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module MarketplaceListingContent
      # Public: render listing content through the Marketplace pipeline.
      #
      # listing - The Marketplace::Listing or Marketplace::Agreement object.
      # attr    - The content attribute (eg. :full_description).
      # context - The Hash with context to pass to the pipeline.
      #
      # Returns the rendered String pipeline output.
      def self.html_for(listing, attr, pipeline_context)
        is_sponsorable = listing.is_a?(SponsorsListing)

        pipeline = if is_sponsorable
          GitHub::Goomba::SponsorsListingPipeline
        else
          GitHub::Goomba::MarketplaceListingPipeline
        end

        content_cache(listing, attr) do
          content = GitHub::HTML::BodyContent.new(
            listing.read_attribute(attr),
            pipeline_context,
            pipeline,
          )

          html = if content.output.is_a?(String)
            content.output
          else
            content.output.to_html
          end

          if content.result[:html_safe]
            html.html_safe # rubocop:disable Rails/OutputSafety
          else
            html
          end
        end
      end

      # Internal: Cache pipeline output for persisted content
      #
      # record  - The Marketplace::Listing or Marketplace::Agreement object.
      # attr    - The content attribute (eg. :full_description)
      #
      # Caches the given block's return value for records that
      # are persisted, and returns the value.
      def self.content_cache(record, attr)
        return yield if record.new_record?

        cache_key = [
          record.class.name.parameterize,
          record.id,
          record.updated_at.iso8601,
          attr,
          "v1",
        ].join(":")

        if (value = GitHub.cache.get(cache_key)).nil?
          value = yield
          GitHub.cache.set(cache_key, value) if value
        end

        value
      end
      private_class_method :content_cache

    end
  end
end
