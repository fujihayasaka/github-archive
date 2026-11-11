# typed: true
# frozen_string_literal: true

module SpokesAPI
  module Types
    # DiffEntry is a wrapper around
    # GitHub::Spokes::Proto::Types::V1::DiffEntry.
    class DiffEntry
      def initialize(pb_diff_entry)
        @pb_diff_entry = pb_diff_entry
      end

      # Public: The string OID of the object before this diff, or
      # GitHub::NULL_OID if the object is new.
      # NOTE: For SHA-256 repos, the fallback NULL_OID will be 40 zeros rather than 64.
      # Callers should use GitRPC::Util.null_oid? for null checks.
      def source_oid
        @pb_diff_entry.source_oid&.id || NULL_OID
      end

      # Public: The string OID of the object after this diff, or
      # GitHub::NULL_OID if the object is deleted.
      # NOTE: For SHA-256 repos, the fallback NULL_OID will be 40 zeros rather than 64.
      # Callers should use GitRPC::Util.null_oid? for null checks.
      def destination_oid
        @pb_diff_entry.destination_oid&.id || NULL_OID
      end

      # Public: The bytes of the object's path before this diff. The returned
      # string uses binary encoding. In most cases, it will be valid UTF-8, but
      # you should verify that it's valid before trying to use it.
      def source_path
        @pb_diff_entry.source&.name
      end

      # Public: The bytes of the object's path after this diff. The returned
      # string uses binary encoding. In most cases, it will be valid UTF-8, but
      # you should verify that it's valid before trying to use it.
      def destination_path
        @pb_diff_entry.destination&.name
      end

      # Public: The type of change. Will be one of:
      #   :STATUS_ADDITION
      #   :STATUS_COPY
      #   :STATUS_DELETION
      #   :STATUS_MODIFICATION
      #   :STATUS_RENAME
      #   :STATUS_TYPE
      #   :STATUS_UNMERGED
      #
      # Any other value is a bug in gitrpcd or git.
      def status
        @pb_diff_entry.status
      end

      # Public: The similarity score for blobs. This will always be an integer.
      # It will only be non-zero when status is :STATUS_COPY or :STATUS_RENAME.
      def score
        @pb_diff_entry.score
      end
    end
  end
end
