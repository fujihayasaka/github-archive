# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesMenuVisibilityTest < GitHub::TestCase
  class MockRepositoryPolicy
    attr_reader :billable_owner

    def initialize(
      can_create_codespaces: false,
      can_see_codespaces_for_pull_request: false,
      billable_owner: nil
    )
      @can_create_codespaces = can_create_codespaces
      @can_see_codespaces_for_pull_request = can_see_codespaces_for_pull_request
      @billable_owner = billable_owner
    end

    def can_attempt_create?
      @can_create_codespaces
    end

    def can_see_codespaces_for_pull_request?
      @can_see_codespaces_for_pull_request
    end
  end

  test "raises ArgumentError is query is nil and user is present", skip_enterprise: true do
    assert_raises(ArgumentError) do
      Codespaces::MenuVisibility.new(user: create(:user))
    end
  end

  context "#has_access_to_codespaces?", skip_enterprise: true do
    test "returns true when the user is present and can create" do
      assert Codespaces::MenuVisibility.new(
        user: create(:user),
        repository_policy: MockRepositoryPolicy.new(
          can_create_codespaces: true
        )
      ).has_access_to_codespaces?
    end

    test "returns false when user is present but can't create" do
      refute Codespaces::MenuVisibility.new(
        user: create(:user),
         repository_policy: MockRepositoryPolicy.new(
          can_create_codespaces: false
        )
      ).has_access_to_codespaces?
    end

    test "returns false when user is not present" do
      refute Codespaces::MenuVisibility.new(user: nil).has_access_to_codespaces?
    end

    test "returns false when codespaces are not enabled" do
      user = create(:user)
      user.stubs(:codespaces_feature_enabled?).returns(false)
      refute Codespaces::MenuVisibility.new(
        user:,
        repository_policy: MockRepositoryPolicy.new(
          can_create_codespaces: true
        )
      ).has_access_to_codespaces?
    end
  end

  context "#can_see_codespaces_for_pull_request?", skip_enterprise: true do
    test "returns true when the user is present, in a PR, can create for PR" do
      repo = create(:repository, from_example: :simple)
      user = create(:user)
      issue = create(:issue, user: user, repository: repo)

      pull = create(:pull_request,
        repository: repo,
        base_ref: "master",
        head_ref: "cr-line-endings",
        issue: issue,
      )

      assert Codespaces::MenuVisibility.new(
        user: user,
        pull_request: pull,
         repository_policy: MockRepositoryPolicy.new(
          can_see_codespaces_for_pull_request: true
        )
      ).can_see_codespaces_for_pull_request?
    end

    test "returns false when the user is present, in a PR, can't create for PR" do
      repo = create(:repository, from_example: :simple)
      user = create(:user)
      issue = create(:issue, user: user, repository: repo)

      pull = create(:pull_request,
        repository: repo,
        base_ref: "master",
        head_ref: "cr-line-endings",
        issue: issue,
      )

      refute Codespaces::MenuVisibility.new(
        user: user,
        pull_request: pull,
        repository_policy: MockRepositoryPolicy.new(
          can_see_codespaces_for_pull_request: false
        )
      ).can_see_codespaces_for_pull_request?
    end

    test "returns false when the user is not present" do
      repo = create(:repository, from_example: :simple)
      user = create(:user)
      issue = create(:issue, user: user, repository: repo)

      pull = create(:pull_request,
        repository: repo,
        base_ref: "master",
        head_ref: "cr-line-endings",
        issue: issue,
      )

      refute Codespaces::MenuVisibility.new(pull_request: pull)
        .can_see_codespaces_for_pull_request?
    end
  end
end
