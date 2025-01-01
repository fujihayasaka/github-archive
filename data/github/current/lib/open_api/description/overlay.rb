# typed: true
# frozen_string_literal: true
require "hana"

module OpenApi
  module Description
    class Overlay

      KEY = "x-github-overlays"
      LEGACY_KEY = "x-githubEnterpriseOverlays"
      MODIFY_KEY = "x-github-modify"

      attr_reader :release_specifications
      attr_reader :patch

      # Public: Find all overlays in an OpenAPI description node
      #
      # node - a Hash
      #
      # Supported formats:
      #
      # Legacy format:
      #
      #     x-githubEnterpriseOverlays:
      #       2.17 || 2.18:
      #         foo: bar
      #       2.19 || 2.20:
      #         foo: baz
      #
      # New formats support more flexible release targeting and overlay
      # effects.
      #
      # Overlay format ("overlay" key); supports adding/replacing values using
      # a JSON Merge Patch:
      #
      #     x-github-overlays:
      #     - releases:
      #       - ghes: [2.17, 2.18]
      #       overlay:
      #         foo: bar
      #     - releases:
      #       - ghes: >= 2.19
      #       overlay:
      #         foo: baz
      #
      # Full format ("patch" key); allows the full range of JSON Patch operations:
      #
      #     x-github-overlays:
      #     - releases:
      #       - ghes: [2.17, 2.18]
      #       patch:
      #       - op: replace
      #         path: /foo
      #         value: bar
      #     - releases:
      #       - ghes: >= 2.19
      #       patch:
      #       - op: replace
      #         path: /foo
      #         value: baz
      #
      # Returns an Array of OpenApi::Description::Overlay instances
      def self.find_all(node, **options)
        return [] unless node
        raw_overlays = []

        types = options[:types] || [KEY, LEGACY_KEY, MODIFY_KEY]

        if types.include?(MODIFY_KEY) && (modify_overlays = node[MODIFY_KEY])
          raw_overlays.push(*convert_modify(modify_overlays))
        end

        if types.include?(LEGACY_KEY) && (legacy_overlays = node[LEGACY_KEY])
          raw_overlays.push(*convert_legacy(legacy_overlays))
        end

        if types.include?(KEY) && node.key?(KEY)
          raw_overlays.push(*node[KEY])
        end

        raw_overlays.map do |raw_overlay|
          parse(raw_overlay, **options)
        end
      end

      # Internal: Parse a raw overlay definition to an instance
      #
      # raw_overlay - a Hash representing the overlay, requirements:
      #
      # - Must have a "releases" key, an Array of String or Hash instances
      #   suitable for OpenApi::Description::ReleaseSpecification.parse
      # - Must have one of these keys:
      #   - "overlay" - a Hash of values to apply to the node (e.g., like
      #     Hash#merge!); short and easy to read
      #   - "patch" - an Array of Hash instances suitable as the input to
      #     Hana::Patch.new; supports full range of JSON Patch (rfc6902)
      #     features.
      #
      # Returns an OpenApi::Description::Overlay instance, or raises an
      # ArgumentError
      def self.parse(raw_overlay, **options)
        release_specifications = raw_overlay.fetch("releases").map do |raw_specification|
          OpenApi::Description::ReleaseSpecification.parse(raw_specification)
        end
        if raw_overlay.key?("patch")
          patch = Hana::Patch.new(raw_overlay["patch"])
        elsif raw_overlay.key?("overlay") && raw_overlay["overlay"].is_a?(Hash)
          patch = MergingPatch.new(raw_overlay["overlay"])
        else
          raise ArgumentError, "Invalid x-github-overlays item: #{raw_overlay.inspect}"
        end
        new(release_specifications, patch)
      end

      # Public: Apply any overlays in an OpenAPI description node (Hash) that
      # match the given release.
      #
      # node - a Hash
      # release - an OpenApi::Description::Release instance
      #
      # Returns the same node Hash; it has been modified in-place.
      def self.apply(node, release, **parser_options)
        overlays = find_all(node, **parser_options.merge(releases: [release]))
        return node if overlays.empty?

        matching = overlays.select { |overlay| overlay.match?(release) }
        unless parser_options[:retain]
          OpenApi.visit(node, ->(n) {
            n.reject! { |k| [KEY, LEGACY_KEY, MODIFY_KEY].include?(k) }
          })
        end
        matching.reduce(node) do |memo, overlay|
          overlay.apply(memo)
        end
      end

      # Internal: Converts a legacy x-githubEnterpriseOverlays definition to an
      #           updated format suitable for parsing.
      #
      # legacy_definition - a Hash
      #
      # Returns a new Hash representation of the overlays
      def self.convert_legacy(legacy_definition)
        legacy_definition.map do |key, data|
          overlay = { "releases" => [] }
          versions = key.strip.split(%r{\s*\|\|\s*})
          overlay["releases"].push({ "ghes" => versions })
          overlay["overlay"] = data
          overlay
        end
      end

      def self.convert_modify(definition)
        definition.map do |release_name, overlay|
          {
            "releases" => [{ release_name => nil }],
            "overlay" => overlay
          }
        end
      end

      # Public: Create an overlay
      #
      # release_specification - an Array of OpenApi::Description::ReleaseSpecification instances
      # patch - Either a Hana::Patch or MergingPatch object. Must respond to apply.
      def initialize(release_specifications, patch)
        @release_specifications = release_specifications
        @patch = patch
      end

      # Internal: Whether a release matches the overlay's requirements
      #
      # release - an OpenApi::Description::Release instance
      #
      # Returns a Boolean
      def match?(release)
        @release_specifications.any? do |release_specification|
          release_specification.match?(release)
        end
      end

      delegate :apply, to: :@patch
    end

    # Minimal implementation of JSON Merge Patch
    class MergingPatch
      attr_reader :data
      def initialize(overlay)
        @data = overlay
      end

      def apply(node)
        merge(node, @data)
      end

      private

      def merge(orig, patch)
        if !orig.is_a?(Hash) || !patch.is_a?(Hash)
          orig = patch
        else
          patch.each_key { |key| orig[key] = merge(orig[key], patch[key]) }
        end

        if orig.is_a?(Hash)
          orig.delete_if { |_k, v| v.nil? }
        else
          orig
        end
      end
    end
  end
end
