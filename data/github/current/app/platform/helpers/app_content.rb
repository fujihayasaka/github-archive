# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module AppContent
      # Public: render GitHub App content through the Marketplace pipeline.
      #
      # app     - the Integration (aka GitHub App) object.
      # attr    - the content attribute (eg. :description).
      # context - the Hash with context to pass to the pipeline.
      #
      # Returns the rendered String pipeline output.
      def self.html_for(app, attr, pipeline_context, truncate: nil, value: nil)
        truncate ||= T.let(nil, T.untyped)
        value ||= T.let(nil, T.untyped)
        content_cache(app, attr) do
          value ||= app.read_attribute(attr)
          truncate ||= value&.length
          formatted = GitHub::Goomba::SimpleDescriptionPipeline.to_html(
            value,
            pipeline_context,
          )

          HTMLTruncator.new(formatted, truncate).to_html(wrap: false)
        end
      end

      # Internal: Cache pipeline output for persisted content
      #
      # record  - The Integration (aka GitHub App) object.
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

        GitHub.cache.fetch(cache_key) { yield }
      end

      private_class_method :content_cache

    end
  end
end
