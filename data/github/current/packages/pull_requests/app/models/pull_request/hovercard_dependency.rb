# typed: true
# frozen_string_literal: true

module PullRequest::HovercardDependency
  REPO_LIMIT_FOR_ORG_HOVERCARD = 5_000
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { PullRequest }


  include UserHovercard::SubjectDefinition

  def user_hovercard_parent
    repository
  end

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :creator, ->(user, viewer, descendant_subjects:) do
      T.bind(self, PullRequest)
      next unless issue && readable_by?(viewer) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      next unless user_id == user.id

      first_in = if user.pull_requests.minimum(:id) == self.id
        "(their first ever)"
      else
        repository = T.must(self.repository)
        # Terminate immediately if we have a nil org.
        org_repo_ids = if repository.organization_id.nil?
          nil
        else
          pr_repo_ids = user.pull_requests.select(:repository_id).distinct.pluck(:repository_id)
          if pr_repo_ids.size <= REPO_LIMIT_FOR_ORG_HOVERCARD
            organization_id = repository.organization_id
            Repositories::Public.filter_repo_ids_to_org(
              organization_id: T.must(organization_id),
              repo_ids: pr_repo_ids
            ).pluck(:id)
          else
            nil
          end
        end

        if org_repo_ids && user.pull_requests.where(repository_id: org_repo_ids).minimum(:id) == self.id
          "(their first in @#{repository.organization})"
        elsif user.pull_requests.for_repository(repository_id).minimum(:id) == self.id
          "(their first in #{repository.nwo})"
        end
      end

      message = ["Opened this pull request", first_in].compact.join(" ")
      Hovercard::Contexts::Custom.new(message, "git-pull-request")
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :codeowner, ->(user, viewer, descendant_subjects:) do
      T.bind(self, PullRequest)
      next unless readable_by?(viewer)

      owned_paths = T.must(codeowners).paths_for_owner(user)
      if owned_paths.any?
        Hovercard::Contexts::Custom.new("Code owner of #{owned_paths.count} #{"file".pluralize(owned_paths.count)} in this pull request", "shield-lock")
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :recency, ->(user, viewer, descendant_subjects:) do
      T.bind(self, PullRequest)
      next unless readable_by?(viewer)

      max_age = 3.months
      suggested_reviewers = PullRequest::SuggestedReviewers.new(self, actor: viewer, max_comment_age: max_age, max_commit_age: max_age).find(limit: nil)
      suggested_reviewer = suggested_reviewers.detect { |sr| sr.user == user }
      next unless suggested_reviewer

      Hovercard::Contexts::Custom.new(suggested_reviewer.description, "clock")
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end
end
