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
    result == :passed ? nil : FAILED_MESSAGE
  end

  class UserStateResult < T::Enum
    enums do
      UserCannotPush = new("USER_CANNOT_PUSH")
      UnverifiedEmail = new("UNVERIFIED_EMAIL")
    end
  end

  def async_condition
    promises = [pull_request.async_base_repository_pushable_by?(user), pull_request.async_base_repository]
    Promise.all(promises).then do |user_can_push_to_base, base_repo|
      if !user_can_push_to_base
        evaluation_result.errors << PullRequests::PageData::MergeBox::MergeRequirementsPayload::FailingSubConditionPayload.new(
          displayName: UserStateResult.serialize(UserStateResult::UserCannotPush),
          message: "User does not have push access to the repository."
        )
      end

      if has_unverified_email?(base_repo)
        evaluation_result.errors << PullRequests::PageData::MergeBox::MergeRequirementsPayload::FailingSubConditionPayload.new(
          displayName: UserStateResult.serialize(UserStateResult::UnverifiedEmail),
          message: "Your email address must be verified before merging."
        )
      end
    end
  end

  sig { override.returns(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionWithSubConditionsPayload) }
  def condition_payload
    PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionWithSubConditionsPayload.new(
      type: merge_condition_type,
      displayName: display_name,
      description: description,
      message: message,
      result:  PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionResult.deserialize(result.to_s.upcase),
      failedSubConditions: evaluation_result.errors
    )
  end

  private

  def has_unverified_email?(base_repository)
    authorization = ContentAuthorizer.authorize(user, :pull_request, :merge, repo: base_repository, owner: T.must(base_repository).owner)
    !authorization.authorized?
  end
end
