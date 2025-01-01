# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class DereferencedReleaseWriter < ReleaseWriter
      def path(format: :json)
        @base_path.join(
          "generated",
          File.basename(@release.filename, ".yaml"),
          "dereferenced",
          File.basename(@release.filename, ".yaml") << file_extension(format)
        )
      end

      def content
        return @content if defined?(@content)
        @content = Marshal.load(Marshal.dump(@release.content))

        # When reading files from disk, cache them here after loading to avoid duplicate loads.
        if expand_references?
          OpenApi::Description::Expander.expand(@content, OpenApi.root.join(@release.filename).to_s, release: @release, api_version: @api_version, scope: @breaking_changes_scope, include_next: @include_next_version, ref_cache: {})
        end

        if @environment == OpenApi::Description::ReleaseWriter::ENV_PUBLIC
          filter!(@content)
        end

        unless @include_webhooks
          filter_webhooks!(@content)
        end

        @content
      end

      def serialize(content, format:)
        if format == :json
          JSON.pretty_generate(content)
        elsif format == :yaml
          YAML.dump(content)
        else
          raise ArgumentError, "Unhandled format #{format}"
        end
      end

      private

      # Private: Construct file extension for output
      #
      # - format - extension [json, yaml]
      def file_extension(format)
        ["", @api_version, "deref", format].compact.join(".")
      end
    end
  end
end
