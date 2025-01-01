# typed: true
# frozen_string_literal: true

module Issue::HovercardDependency
  REPO_LIMIT_FOR_ORG_HOVERCARD = 5_000
  extend T::Helpers
  extend ActiveSupport::Concern

  include UserHovercard::SubjectDefinition

  requires_ancestor { Issue }

  def user_hovercard_parent
    repository
  end

  def first_issue_in_organization?(user, issue_id, organization_id)
    repo_ids = Repository.where(organization_id: organization_id).pluck(:id)
    repo_ids.size <= REPO_LIMIT_FOR_ORG_HOVERCARD && user.issues.where(repository_id: repo_ids).minimum(:id) == issue_id
  end

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :creator, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Issue)
      repository = T.must(self.repository)

      next unless readable_by?(viewer)
      next unless user_id == user.id

      # compute min id using created_at, to avoid scanning all of user's issues
      first_in = if user.issues.order(:created_at, :id).pick(:created_at, :id)[1] == self.id
        "(their first ever)"
      elsif repository.organization_id && first_issue_in_organization?(user, self.id, repository.organization_id)
        "(their first in @#{T.must(repository.organization).display_login})"
      elsif user.issues.for_repository(repository_id).minimum(:id) == self.id
        "(their first in #{repository.name_with_display_owner})"
      end

      message = ["Opened this issue", first_in].compact.join(" ")
      Hovercard::Contexts::Custom.new(message, "issue-opened")
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end
end
