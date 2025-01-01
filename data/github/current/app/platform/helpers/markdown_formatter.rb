# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Platform
  module Helpers
    class MarkdownFormatter
      include ::ActionView::Helpers::TagHelper
      include ::BlobMarkupHelper
      include ::TextHelper
      include ::FailbotHelper

      def initialize(viewer:, blob:, repository:, committish:, absolute_path:)
        @viewer = viewer
        @blob = blob
        @repository = repository
        @absolute_path = absolute_path
        @committish = committish
      end

      def format_content
        if GitHub::HTML::MarkupFilter.can_render_blob?(@blob) || @blob.viewable?
          context = {}
          context[:current_user] = @viewer
          context[:path] = File.dirname(@blob.path)
          context[:absolute_path] = @absolute_path
          context[:entity] = @repository
          context[:committish] = @committish
          context[:view] = :tree

          context = blob_html_context(@blob).update(context)
          result = markup_blob!(@blob, context)
          output = result[:output]
          output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety

          if result[:rendered]
            formatted_blob_content output
          else
            plaintext_blob_content output
          end
        end
      rescue => e # rubocop:todo Lint/RescueException
        failbot(e)
        plaintext_blob(@blob)
      end

      def markup_blob!(blob, context)
        start = GitHub::Dogstats.monotonic_time
        begin
          Timeout.timeout 5 do
            result = GitHub::Goomba::PlatformMarkupPipeline.call(nil, context)
            GitHub.dogstats.timing_since("blob.process.mobile.markup.success", start)
            result
          end
        rescue Exception # rubocop:todo Lint/RescueException
          GitHub.dogstats.timing_since("blob.process.mobile.markup.error", start)
          raise # rubocop:disable GitHub/UsePlatformErrors
        end
      end

      # Internal: The context to use when rendering a blob through the HTML pipeline
      #
      # Returns a Hash
      def blob_html_context(blob)
        context = {}
        context[:blob] = blob
        context[:name] = blob.path
        context[:anchor_icon] = octicon("link")

        context[:highlight] = "coffee" if blob.name =~ /litcoffee$/

        # allow "foo.coffee.md" or "foo.rb.md" to specify a default highlight
        segments = File.basename(blob.name).split(".")[1..-2]
        extension = segments.try(:last)

        if extension.present?
          context[:highlight] = LITERATE_EXTENSIONS[extension] || extension
        end

        context
      end

    end
  end
end
