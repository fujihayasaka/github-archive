# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class CommitComment < Connections::Base
      total_count_field

      def total_count
        case @object
        when Platform::ConnectionWrappers::ArrayWrapper, Platform::ConnectionWrappers::StableArray
          @object.total_count
        else
          attrs = @object.items.where_values_hash

          repo_id = attrs.fetch("repository_id", nil)
          user_id = attrs.fetch("user_id", nil)

          if repo_id.nil? && user_id.nil?
            0
          elsif user_id.present?
            @object.items.count
          elsif commit_id = attrs.fetch("commit_id", nil)
            if commit_id.is_a?(Array) || repo_id.is_a?(Array)
              # This happens when we are loading the comments for a group of commits or repos
              # instead of a single commit. This happens when loading the comments for a
              # Comparison, for example.
              @object.items.count
            else
              Loaders::CommitCommentCount.load(repo_id, commit_id)
            end
          else
            Loaders::RepositoryCommitCommentCount.load(repo_id)
          end
        end
      end
    end
  end
end
