# typed: true
# frozen_string_literal: true

module PullRequests
  module Errors
    class BadRange < StandardError; end
    class FilesUnavailable < StandardError; end

    class NonCanonicalRange < StandardError
      attr_accessor :canonical_range

      def initialize(canonical_range)
        @canonical_range = canonical_range
      end
    end

    class OrphanCommit < StandardError
      attr_accessor :oid2

      def initialize(oid2)
        @oid2 = oid2
      end
    end
  end
end
