# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class ContributionsDependencyTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd
    @organization = create(:organization)
    @user = @organization.admins.first
    @repo = create :repository, owner: @user, from_example: :repository_test_simple
  end

  setup do
    Spokesd.enable_spokesd
  end

  context "#first_time_contributions" do
    test "finds first time contributions" do
      new_user = create(:user)
      pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: new_user)
      pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)

      first_time_contributions = @repo.first_time_contributions([pr_1, pr_2])

      assert_same_elements first_time_contributions, [pr_1, pr_2]
    end

    test "takes earliest contribution when multiple" do
      pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)
      pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)

      first_time_contributions = @repo.first_time_contributions([pr_1, pr_2])

      assert_same_elements first_time_contributions, [pr_1]
    end

    test "ignores previous contributor" do
      new_user = create(:user)
      pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)
      pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)
      pr_3 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: new_user)
      pr_4 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: new_user)

      first_time_contributions = @repo.first_time_contributions([pr_2, pr_3, pr_4])

      assert_same_elements first_time_contributions, [pr_3]
    end

    test "ignores all previous contributors" do
      new_user = create(:user)
      pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)
      pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: new_user)
      pr_3 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @user)
      pr_4 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: new_user)

      first_time_contributions = @repo.first_time_contributions([pr_3, pr_4])

      assert_same_elements first_time_contributions, []
    end
  end
end
