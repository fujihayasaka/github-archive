# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestUserState < MergeConditions::BaseMergeCondition
  FAILED_MESSAGE = "User is unable to merge this pull request."

  def display_name
    "Pull request user state"
  end

  def description
    "The user must have push access to the repo and a verified email"
  end

  def message
    # TODO: make this more specific about what failed
    result == :passed ? nil : FAILED_MESSAGE
  end

  def async_condition
    promises = [pull_request.async_base_repository_pushable_by?(user), pull_request.async_base_repository]
    Promise.all(promises).then do |user_can_push_to_base, base_repo|
      if !user_can_push_to_base
        evaluation_result.errors << "User cannot push to base."
      end

      if has_unverified_email?(base_repo)
        evaluation_result.errors << "User has not verified email."
      end
    end
  end

  private

  def has_unverified_email?(base_repository)
    authorization = ContentAuthorizer.authorize(user, :pull_request, :merge, repo: base_repository, owner: T.must(base_repository).owner)
    !authorization.authorized?
  end
end
