# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryPostProcessor < BasePostProcessor
      def joins
        %i(issues commit_comments)
      end

      # Public: Post process a repository
      def process(repo, attributes, batch_load_associations: false)
        repo.update(template: true) if is_template?(attributes)
        repo.set_archived if archived?(attributes)

        ActiveRecord::Base.connected_to(role: :writing) do
          # Refresh Actions Workflow UI
          repo.refresh_workflows
        end

        if batch_load_associations
          # Batch load issue associations to set sequence

          # Fix sorbet linter errors
          max_number = T.let(0, T.untyped)

          issue_ids = repo.issues.pluck(:id)

          issue_ids.each_slice(BATCH_SIZE) do |issue_batch_ids|
            max_number_batch = Issue.where(id: issue_batch_ids).maximum(:number)
            max_number = max_number_batch if max_number_batch > max_number
          end

          Sequence.set(repo, max_number) if max_number > 0

          # Batch load commit comments to rewrite body
          commit_comment_ids = repo.commit_comments.pluck(:id)

          commit_comment_ids.each_slice(BATCH_SIZE) do |commit_comment_batch_ids|
            CommitComment.where(id: commit_comment_batch_ids).find_each do |commit_comment|
              rewrite_commit_cmment(commit_comment)
            end
          end
        else
          if issue_sequence_number = repo.issues.maximum(:number)
            Sequence.set(repo, issue_sequence_number)
          end

          repo.commit_comments.each do |comment|
            rewrite_commit_cmment(comment)
          end
        end

        if first_milestone = repo.milestones.first
          if !Sequence.exists? first_milestone
            Sequence.create first_milestone
          end

          number = repo.milestones.maximum(:number)
          Sequence.set(first_milestone, number)
        end

        RepositoryCheckPreferredFilesJob.perform_later(repo.id, repo.default_oid)
        RepositoryUpdateLanguageStatsJob.perform_later(repo.id)
      end

      private

      def archived?(attributes)
        attributes[:is_archived] == true
      end

      def rewrite_commit_cmment(comment)
        rewritten_body = user_content_rewriter.process(comment)
        return if comment.body == rewritten_body
        comment.update_column(:body, rewritten_body)
      end

      def is_template?(attributes)
        attributes.fetch(:general_settings, {}).fetch(:template, false)
      end
    end
  end
end
