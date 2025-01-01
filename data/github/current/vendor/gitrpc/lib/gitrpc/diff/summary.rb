# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/diff/summary/common"
require "gitrpc/diff/summary/delta"

module GitRPC
  class Diff
    class Summary

      include GitRPC::Diff::Summary::Common

      def self.parse(output)
        GitRPC::Diff::DiffTreeParser.new(output).parse_summary
      end

      def self.unavailable(reason:, error:)
        new(available: false, unavailable_reason: reason, unavailable_error: error)
      end

      def self.empty
        new(additions: 0, deletions: 0, changed_files: 0, deltas: [])
      end

      # The total files changed in the diff
      attr_reader :changed_files

      # Details on the changes in each file. A list of GitRPC::Diff::Summary::Delta objects
      attr_reader :deltas

      # The count of files added in this diff
      attr_reader :files_added

      # The count of files removed in this diff
      attr_reader :files_removed

      # The count of files modified in this diff
      attr_reader :files_modified

      attr_reader :additions
      attr_reader :deletions
      attr_reader :unavailable_reason
      attr_reader :unavailable_error

      def initialize(additions: 0, deletions: 0, changed_files: 0, deltas: [], available: true, unavailable_reason: nil, unavailable_error: nil)
        @available          = available
        @unavailable_reason = unavailable_reason
        @unavailable_error  = unavailable_error

        @files_modified = 0
        @files_added    = 0
        @files_removed  = 0

        @additions      = additions
        @deletions      = deletions
        @changed_files  = changed_files

        @deltas         = deltas.dup.freeze

        @deltas.each do |delta|
          case delta.status
          when "M" then @files_modified += 1
          when "A" then @files_added += 1
          when "D" then @files_removed += 1
          end
        end

        freeze
      end

      def too_many_files?
        changed_files > max_files
      end

      def available?
        @available
      end

      def max_files
        GitRPC::Diff::DiffTreeParser::MAX_FILES
      end
    end
  end
end
