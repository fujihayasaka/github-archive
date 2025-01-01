# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module MergeCommitUpdateRef
      extend T::Sig

      sig { returns(String) }
      def merge_commit_update_refs_github_app_slug
        "github-merge-commit-update-refs"
      end

      sig { returns(String) }
      def merge_commit_update_refs_github_app_name
        "GitHub Merge Commit Update Refs"
      end

      sig { returns(T.nilable(Bot)) }
      def merge_commit_update_refs_bot
        return @merge_commit_update_refs_bot if defined?(@merge_commit_update_refs_bot)

        integration_id = Apps::Internal::MergeCommitUpdateRefs.id
        @merge_commit_update_refs_bot = T.let(integration_id != nil ? Integration.find(integration_id).bot : nil, T.nilable(Bot))
      end
    end
  end

  extend Config::MergeCommitUpdateRef
end
