# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestUserState < MergeConditions::BaseMergeCondition
  FAILED_MESSAGE = "User is not allowed to push to this repository"

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
    if FeatureFlag.vexi.enabled?(:prs_user_state_for_integrations, default: false)
      async_condition_with_integration_support
    else
      async_condition_without_integration_support
    end
  end

  def async_condition_with_integration_support
    pull_request.async_base_repository.then do |base_repo|
      async_user_can_push_to_repo?(base_repo).then do |user_can_push|
        if !user_can_push
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
  end

  def async_condition_without_integration_support
    promises = [
      pull_request.async_base_repository_pushable_by?(user),
      pull_request.async_base_repository
    ]
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

  # Check if user can push to the base repository
  def async_user_can_push_to_repo?(base_repo)
    return Promise.resolve(false) unless base_repo
    return Promise.resolve(false) unless user

    if user.is_a?(Bot)
      # For bots/integrations, load granular actor and check permissions
      async_bot_can_push_to_repo?(base_repo)
    else
      # For regular users, use the standard pushable check
      pull_request.async_base_repository_pushable_by?(user)
    end
  end

  # Check if a bot can push to a specific repository
  # This loads the granular actor (installation) for that repository first,
  # matching the legacy async_authorized_to_write? behavior
  def async_bot_can_push_to_repo?(repo)
    return Promise.resolve(false) unless repo

    load_actor = user.respond_to?(:async_load_granular_actor_for) ? user.async_load_granular_actor_for(repo) : Promise.resolve(user)
    load_actor.then do
      next false unless user.ability_delegate

      # Match the legacy async_authorized_to_write? behavior for bots with static permissions
      app = T.must(user.integration)
      if FeatureFlag.vexi.enabled?(:repo_authorized_to_write_static_app_repo_perms, app, default: false) &&
        Apps::Privileged.capable?(:static_installation_repository_permissions, app: app)
        next repo.resources.metadata.async_readable_by?(user) && app.default_permissions["contents"] == :write
      end

      repo.resources.contents.async_writable_by?(user)
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
