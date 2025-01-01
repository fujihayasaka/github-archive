# typed: true
# frozen_string_literal: true

module Label::DiscussionsDependency
  extend T::Helpers

  requires_ancestor { Label }

  # Public: Get issues that a particular user can convert into discussions.
  #
  # actor - the currently authenticated User
  #
  # Returns an Array of Issues that have this Label.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def convertable_issues(actor)
    return [] unless T.cast(repository, T.nilable(Repository))&.can_convert_issues_to_discussions?(actor) # rubocop:todo GitHub/AvoidCast

    issues.open_issues.without_pull_requests.select do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue.can_be_converted_by?(actor)
    end
  end
end
