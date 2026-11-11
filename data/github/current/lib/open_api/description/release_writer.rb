# typed: false
# frozen_string_literal: true

module OpenApi
  module Description
    class ReleaseWriter
      # OpenAPI description made to be public (SDKs, Documentation)
      ENV_PUBLIC = :public
      # OpenAPI description content for internal use (Validation, Tools)
      ENV_INTERNAL = :internal

      ENVIRONMENTS = [ENV_PUBLIC, ENV_INTERNAL].freeze

      def self.write(release, format: :json, base_path:, breaking_changes_scope: nil, api_version: nil, include_next_version: false, include_webhooks: false, expand_references: true)
        new(release, base_path: base_path, breaking_changes_scope: breaking_changes_scope, api_version: api_version, include_next_version: include_next_version, include_webhooks: include_webhooks, expand_references: expand_references).write(format: format)
      end

      def self.content(release)
        new(release).content
      end

      def initialize(release, base_path: OpenApi.root, breaking_changes_scope: nil, api_version: nil, environment: ENV_PUBLIC, include_next_version: false, include_webhooks: false, expand_references: true)
        @release                = release
        @base_path              = base_path
        @breaking_changes_scope = breaking_changes_scope
        @api_version            = api_version
        @include_next_version   = include_next_version
        @include_webhooks       = include_webhooks
        @expand_references      = expand_references

        if ENVIRONMENTS.include?(environment)
          @environment = environment
        else
          raise ArgumentError, "Unknown Release Environment #{environment}"
        end
      end

      def expand_references?
        @expand_references
      end

      # Path to the output file
      def path
        raise NotImplementedError, "Must be implemented"
      end

      # Build/reformat release content
      def content
        raise NotImplementedError, "Must be implemented"
      end

      # Serialize to write
      def serialize(content)
        raise NotImplementedError, "Must be implemented"
      end

      def write(format:)
        # Ensure the directory exists
        out_path = path(format: format)
        out_path.dirname.mkpath
        # Write the output
        wrote_bytes = out_path.write(serialize(content, format: format))
        # Return some stats for reporting
        [out_path.relative_path_from(GitHub::AppEnvironment.root), wrote_bytes]
      end

      private

      def yaml_serialize_null_enums(content)
        # dump out initial YAML text from content
        yaml = Psych.dump(content)
        stream = Psych.parse_stream(yaml)

        stream.grep(Psych::Nodes::Mapping).each do |node|
          # for each mapping found in the document, we want to locate any that match this shape:
          #
          # [name]:
          #   nullable: true
          #   enum:
          #     - [value]
          #     - [value]
          #     - null
          #     - [value]
          #   [other fields]
          #
          # When we deserialize the `Psych.dump` output we'll see the `null` value has been removed. This confuses
          # some parsers, which ignore the whitespace and try to look for additional data, and complain that the
          # subsequent indenting is incorrect.
          #
          # This also doesn't match what the OpenAPI 3 standard expects https://swagger.io/docs/specification/data-models/enums/
          #
          # The below finds any matches of the following shape and locates the `null` node, reformatting it into the
          # correct shape for serialization.
          node.children.each_slice(2) do |_, v|
            if v.is_a?(Psych::Nodes::Mapping)
              nullable_node = v.children.each_slice(2).select { |k, v| k.is_a?(Psych::Nodes::Scalar) && k.value == "nullable" && v.is_a?(Psych::Nodes::Scalar) && v.value == "true" }
              enum_matches = v.children.each_slice(2).select { |k, v| k.is_a?(Psych::Nodes::Scalar) && k.value == "enum" && v.is_a?(Psych::Nodes::Sequence)  }

              next unless nullable_node.any? && enum_matches.any?

              enum_matches.each do |_, sequence|
                null_value_scalars = sequence.select { |s| s.is_a?(Psych::Nodes::Scalar) && s.value == "" }
                null_value_scalars.each { |node| node.value = "null" }
              end
            end
          end
        end

        stream.to_yaml
      end

      def filter!(node, parent = nil)
        case node
        when Hash
          # x-unpublished for properties
          node.reject! { |_, v| v.is_a?(Hash) && v.key?("x-unpublished") }

          # There may be x- keys when they define actual properties
          strip_extended_properties!(node) unless %w[properties headers].include?(parent)

          if parent == "properties"
            # response properties are often used to refer to references which may be currently unpublished
            node.reject! { |_, v| v.is_a?(Hash) && v.length == 1 && v.key?("$ref") && v["$ref"].is_a?(String) && is_unpublished_reference(v["$ref"]) }
          end

          node.each { |k, v| filter!(v, k) }
        when Array
          node.reject! { |v| v.is_a?(Hash) && v.key?("x-unpublished") }

          if parent == "parameters"
            # review $ref nodes and strip out any that point to x-unpublished entries
            node.reject! { |v| v.is_a?(Hash) && v.key?("$ref") && is_unpublished_reference(v["$ref"]) }
          end

          node.each { |n| filter!(n, parent) }
        end
      end

      # Removes webhooks top level key: 'webhooks' in 3.1+, 'x-webhooks' in 3.0
      # Makes changes in-place.
      def filter_webhooks!(node)
        node.reject! { |k, _| %w[webhooks x-webhooks].include?(k) }
      end

      PUBLIC_EXTENSIONS = %w[x-github x-multi-segment x-github-breaking-changes x-webhooks x-github-plan x-github-release].freeze

      def public_extension?(ext)
        # x-github-breaking-changes should be removed if not api versioning
        if !@api_version && !@breaking_changes_scope && ext == "x-github-breaking-changes"
          false
        else
          PUBLIC_EXTENSIONS.include?(ext)
        end
      end

      # Internal: Strip any disallowed x- properties.
      #
      # value - a Hash (node in the document)
      #
      # Makes changes in-place.
      def strip_extended_properties!(value)
        value.reject! { |k, _v| k.start_with?("x-") && !public_extension?(k) }
      end

      def is_unpublished_reference(path)
        return false unless path.match?("^#")

        path_without_hash = path.gsub(/\#\//, "")
        path_segments = path_without_hash.split("/").compact
        match = content.dig(*path_segments)

        # if we can't match on this node, this is an invalid reference and we should scrub this ref
        return true unless match
        # if we match on a node and the hash has an `x-unpublished` key it will be scrubbed, so we should scrub this reference
        return true if match.is_a?(Hash) && match.key?("x-unpublished")

        false
      end
    end
  end
end
