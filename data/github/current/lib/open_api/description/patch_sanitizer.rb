# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    # PatchSanitizer strips internal-only metadata from JSON Patch operations
    # before they are either:
    #   1. Passed to Hana::Patch (which strictly validates RFC 6902 and rejects
    #      unknown keys on a patch op), or
    #   2. Retained on the bundled output for `:partial` breaking-changes scope,
    #      where the `x-github-breaking-changes` block stays in the published
    #      rest-api-description and would otherwise leak this metadata.
    #
    # Note: this is distinct from
    # OpenApi::Description::ReleaseWriter#strip_extended_properties!, which
    # filters disallowed `x-*` keys at the schema-node level on the rendered
    # document. PatchSanitizer operates on JSON Patch *op* hashes (which have
    # their own RFC 6902 schema, separate from OpenAPI extension rules).
    #
    # Currently strips:
    #   - "expected_value": a precondition recorded on positional array patches
    #     so the lint suite can detect when the underlying list has been
    #     reordered, invalidating the patch index. See
    #     test/fast/linting/api_breaking_changes_positional_patches_test.rb
    module PatchSanitizer
      METADATA_KEYS = %w[expected_value].freeze

      # Public: Returns a new patch (Array of Hash op) with metadata keys removed.
      # Accepts an Array, a single Hash op, or anything else (returned as-is).
      def self.sanitize(patch)
        case patch
        when Array
          patch.map { |op| sanitize_op(op) }
        when Hash
          sanitize_op(patch)
        else
          patch
        end
      end

      # Public: Mutates `patch` in place to remove metadata keys from each op.
      # Use this when the patch is retained on a node that gets serialized
      # downstream (e.g. partial-scope breaking changes).
      def self.sanitize!(patch)
        case patch
        when Array
          patch.each { |op| sanitize_op!(op) }
        when Hash
          sanitize_op!(patch)
        end
        patch
      end

      def self.sanitize_op(op)
        return op unless op.is_a?(Hash)
        return op if (op.keys & METADATA_KEYS).empty?
        op.reject { |k, _| METADATA_KEYS.include?(k) }
      end

      def self.sanitize_op!(op)
        return op unless op.is_a?(Hash)
        METADATA_KEYS.each { |k| op.delete(k) }
        op
      end
    end
  end
end
