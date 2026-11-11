# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class FilesProvider < PrefetchedProvider
      EMPTY_RESULTS = [Results::FileResult.new(object: nil, base_file_path: "", paths: [])]

      def self.modes
        [:files]
      end

      def self.type
        "files"
      end

      def search(_)
        return EMPTY_RESULTS unless scope_matches?

        branch = scope.repository.default_branch
        ref = scope.repository.heads.find(branch)&.sha

        return EMPTY_RESULTS if ref.nil?

        [
          Results::FileResult.new(
            object: scope.repository,
            base_file_path: blob_path(scope.owner, scope.repository, branch, ""),
            paths: scope.repository.tree_file_list(ref)
          )
        ]
      end
    end
  end
end
