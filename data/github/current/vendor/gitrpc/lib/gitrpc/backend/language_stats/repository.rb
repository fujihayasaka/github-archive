# typed: true
# frozen_string_literal: true

require "linguist"
require "gitrpc/backend/language_stats/diff"
require "gitrpc/backend/readers/attribute_reader"
require "gitrpc/backend/readers/object_reader"

module GitRPC
  class Backend
    module LanguageStats
      class Repository < ::Linguist::Source::Repository
        def initialize(backend)
          @backend = backend
        end

        def path
          @backend.path
        end

        def diff(old_commit, new_commit)
          args = ["-z", "-r", "--raw", "--end-of-options"]
          args << (old_commit.nil? ? @backend.hash_algo.empty_tree : old_commit)
          args << (new_commit.nil? ? @backend.hash_algo.empty_tree : new_commit)
          res = @backend.checked_spawn_git!("diff-tree", args)
          Diff.new(res["out"])
        end

        def get_tree_size(commit_id, limit = nil)
          args = ["-r", "--object-only", "-z"]
          args << "--max-count=#{limit}" unless limit.nil? || limit < 0
          args.push("--end-of-options", commit_id)

          res = @backend.checked_spawn_git!("ls-tree", args)
          res["out"].split("\0").count
        end

        def load_attributes_for_path(path, attr_names)
          if @attr_reader && @attr_reader.attributes != attr_names
            @attr_reader.close
            @attr_reader = nil
          end

          @attr_reader ||= AttributeReader.new(@backend.native, source: @attr_source, attributes: attr_names)
          @attr_reader.get_attributes(path)
        end

        def load_blob(blob_id, max_size)
          if @obj_reader && @obj_reader.limit != max_size
            @obj_reader.limit = max_size
          end

          @obj_reader ||= ObjectReader.new(@backend.native, limit: max_size)
          obj = @obj_reader.object(blob_id, :contents, true)
          [obj[:data], obj[:size]]
        end

        def set_attribute_source(commit_id)
          if @attr_reader && @attr_reader.source != commit_id
            @attr_reader.close
            @attr_reader = nil
          end

          @attr_source = commit_id
        end

        def close_readers
          @attr_reader.close unless @attr_reader.nil?
          @obj_reader.close unless @obj_reader.nil?

          @attr_reader = @obj_reader = nil
        end
      end
    end
  end
end
