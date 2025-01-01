# typed: true
# frozen_string_literal: true

module Issue::PinDependency
  extend T::Helpers

  requires_ancestor { Issue }

  def pin(actor:)
    repository = T.must(self.repository)

    return if !repository.can_pin_issues?(actor) || self.pull_request? ||
    repository.pinned_issues.find_by(issue_id: id) || repository.pinned_issues.count >= Repository::PinnedIssuesDependency::PINNED_ISSUES_LIMIT

    Repository.transaction do
      pinned = repository.pinned_issues.create!(issue: self, pinned_by: actor, sort: repository.pinned_issues.pluck(:sort).max.to_i + 1)
    end
  end

  def unpin(actor:)
    repository = T.must(self.repository)

    return if !repository.can_pin_issues?(actor)

    if pinned_issue = repository.pinned_issues.find_by(issue_id: id)
      pinned_issue.destroy
      pinned_issue.generate_unpinned_event(actor: actor)
      pinned_issue
    end
  end

  def pinned?
    !!pinned_issue
  end
end
