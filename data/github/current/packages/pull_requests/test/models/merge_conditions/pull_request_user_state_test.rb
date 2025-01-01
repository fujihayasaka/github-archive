# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestUserStateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
    @rando = create(:user)
  end

  test "stateless methods" do
    merge_condition = MergeConditions::PullRequestUserState.new(@pull, @owner, :merge)

    assert_equal "Pull request user state", merge_condition.display_name
    assert_equal "The user must have push access to the repo and a verified email", merge_condition.description
  end

  test "fails when user does not have write access to repo" do
    merge_condition = MergeConditions::PullRequestUserState.new(@pull, @rando, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestUserState::FAILED_MESSAGE, merge_condition.message
    assert_equal [{
      displayName: "USER_CANNOT_PUSH",
      message: "User does not have push access to the repository.",
    }].as_json, merge_condition.condition_payload.failedSubConditions.as_json
  end

  test "fails when user has not verified email" do
    # Email verification is part of the PullRequestAuthorizer, so stub this
    # rather than do elaborate setup
    auth_object = ContentAuthorizer::PullRequestAuthorizer.new(@owner, :merge, {})
    ContentAuthorizer.stubs(:authorize).returns(auth_object)
    auth_object.stubs(:authorized?).returns(false)

    merge_condition = MergeConditions::PullRequestUserState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestUserState::FAILED_MESSAGE, merge_condition.message
    assert_equal [PullRequests::PageData::MergeBox::MergeRequirementsPayload::FailingSubConditionPayload.new(
      displayName: "UNVERIFIED_EMAIL",
      message: "Your email address must be verified before merging."
    )].as_json, merge_condition.condition_payload.failedSubConditions.as_json
  end

  test "passes when user has write access to repo and has verified email" do
    # Email verification is part of the PullRequestAuthorizer, so stub this
    # rather than do elaborate setup
    auth_object = ContentAuthorizer::PullRequestAuthorizer.new(@owner, :merge, {})
    ContentAuthorizer.stubs(:authorize).returns(auth_object)
    auth_object.stubs(:authorized?).returns(true)

    merge_condition = MergeConditions::PullRequestUserState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
    assert_nil merge_condition.message
    assert_equal [], merge_condition.condition_payload.failedSubConditions
  end
end
