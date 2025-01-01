# typed: true
# frozen_string_literal: true

require "test_helper"

class TopRepositoriesTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)
    @repos = create_list(:repository, 9, owner: @user)
  end

  test "can paginate repositories" do
    GitHub.flipper[:repositories_finder_default_order].enable

    page1 = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).simple_paginate(per_page: 5, page: 1)
    assert_equal 5, page1.length
    assert_equal 2, page1.next_page
    assert_nil page1.previous_page

    page2 = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).simple_paginate(per_page: 5, page: 2)
    assert_equal 4, page2.length
    assert_nil page2.next_page
    assert_equal 1, page2.previous_page

    assert_equal 9, (page1 + page2).uniq(&:id).length
  end

  test "can paginate repositories, large scope" do
    GitHub.flipper[:repositories_finder_default_order].enable

    RepositoriesFinder.stub_const(:LARGE_IDS_THRESHOLD, 1) do
      page1 = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).simple_paginate(per_page: 5, page: 1)
      assert_equal 5, page1.length
      assert_equal 2, page1.next_page
      assert_nil page1.previous_page

      page2 = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).simple_paginate(per_page: 5, page: 2)
      assert_equal 4, page2.length
      assert_nil page2.next_page
      assert_equal 1, page2.previous_page

      assert_equal 9, (page1 + page2).uniq(&:id).length
    end
  end

  test "filters resources using unauthorized organization ids" do
    unauthorized_repo = create(:repository)
    unauthorized_repo.add_member(@user)
    create(:commit_contribution, repository: unauthorized_repo, user: @user, committed_date: 1.day.ago)

    repos = TopRepositories.for(viewer: @user, cap_filter: cap_unauthorizing_filter(unauthorized_repo)).to_a

    # assert_equal 9, repos.length
    refute_includes repos, unauthorized_repo
  end

  test "includes contributed repositories with contributions 4 months or sooner by default" do
    contributed_repo = create(:repository)
    contributed_repo.add_member(@user)
    create(:commit_contribution, repository: contributed_repo, user: @user, committed_date: 1.day.ago)

    old_contributed_repo = create(:repository)
    create(:commit_contribution, repository: old_contributed_repo, user: @user, committed_date: 5.months.ago)

    repos = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).to_a

    assert_includes repos.map(&:id), contributed_repo.id
    refute_includes repos.map(&:id), old_contributed_repo.id
  end

  test "includes contributed repositories up to a year ago" do
    contributed_repo = create(:repository)
    contributed_repo.add_member(@user)
    create(:commit_contribution, repository: contributed_repo, user: @user, committed_date: 11.months.ago)

    old_contributed_repo = create(:repository)
    # old_contributed_repo.add_member(@user)
    create(:commit_contribution, repository: old_contributed_repo, user: @user, committed_date: 2.years.ago)

    repos = TopRepositories.for(viewer: @user, since: 2.years.ago, cap_filter: cap_authorizing_filter).to_a

    assert_includes repos.map(&:id), contributed_repo.id
    refute_includes repos.map(&:id), old_contributed_repo.id
  end

  test "filters ranked repositories using unauthorized_organization_ids" do
    contributed_repo = create(:repository)
    contributed_repo.add_member(@user)
    create(:commit_contribution, repository: contributed_repo, user: @user, committed_date: 1.day.ago)

    repos = TopRepositories.for(viewer: @user, cap_filter: cap_unauthorizing_filter(contributed_repo)).to_a

    refute_includes repos.map(&:id), contributed_repo.id
  end

  test "large bot accounts do not see ranked repositories" do
    contributed_repo = create(:repository)
    create(:commit_contribution, repository: contributed_repo, user: @user, committed_date: 1.day.ago)

    @user.stubs(:large_bot_account?).returns(true)

    repos = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).to_a

    refute_includes repos.map(&:id), contributed_repo.id
  end

  test "includes repositories where the viewer is a member with no collaborations" do
    contributed_repo = create(:repository)
    contributed_repo.add_member(@user)
    repos = TopRepositories.for(viewer: @user, cap_filter: cap_authorizing_filter).to_a
    assert_includes repos.map(&:id), contributed_repo.id
  end
end
