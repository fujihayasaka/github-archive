# typed: true
# frozen_string_literal: true

require "linguist"
require "strscan"

module GitRPC
  class Backend
    module LanguageStats
      class Diff < Linguist::Source::Diff
        def initialize(raw_tree_diff)
          delta_map = {}
          scanner = StringScanner.new(raw_tree_diff)

          # Scan for raw diff info
          while scanner.scan(GitRPC::Diff::DiffTreeParser::RAW_MATCHER)
            delta = Delta.new(scanner)
            delta_map[delta.new_file[:path]] = delta
          end

          # TODO: to mimic the legacy Rugged/libgit2 implementation, we don't
          # actually check whether the delta is binary. It is possible to do
          # that, though, by adding a '--numstat' to the diff, scanning the
          # result with 'GitRPC::Diff::DiffTreeParser::NUMSTAT_MATCHER', and
          # marking files with "-" for additions/deletions as binary.

          @deltas = delta_map.values
        end

        def each_delta(&block)
          @deltas.each(&block)
        end
      end

      class Delta < Linguist::Source::Diff::Delta
        attr_reader :status, :old_file, :new_file

        def initialize(match, binary = false)
          @status = GitRPC::Diff::StatusMethods::LABELS[match["status"]].to_sym
          @status = :modified if @status == :changed # Linguist expects type changes with status "modified"

          @binary = binary
          @old_file = {
            oid: match["old_oid"],
            mode: match["old_mode"].to_i(8),
            path: match["src_path"]
          }
          @new_file = {
            oid: match["new_oid"],
            mode: match["new_mode"].to_i(8),
            path: match["dst_path"] || match["src_path"]
          }
        end

        def binary?
          @binary
        end

        def binary=(binary)
          @binary = binary
        end
      end
    end
  end
end
