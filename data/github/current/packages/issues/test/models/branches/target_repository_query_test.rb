# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

# This test logic was pulled almost entirely from
# the CodespacesRepositorySelectViewTest
class BranchesTargetRepositoryQueryTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include DogstatsTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @admin = create(:user)
    @member = create(:user)
    @forker = create(:user)
    @org = create(:business_plus_organization, admin: @admin)
    @team = create(:team, organization: @org)
    @org_owned_repo = create(:public_repository, owner: @org)
    @org_owned_private_repo = create(:private_repository, owner: @org)


    @org.add_member(@member)
    @team.add_member(@member)
    @team.add_repository(@org_owned_repo, :admin)
    @team.add_repository(@org_owned_private_repo, :admin)

    create(:commit_contribution,
           repository: @org_owned_repo,
           user: @member,
           commit_count: 1,
           committed_date: Time.zone.today)

    @repo = create(:public_repository, owner: @member, name: "member repo", from_example: :review_comment_source)
    @forked_repo = create(:fork_repository, forker: @forker, fork_repo: @repo)
    make_searchable @repo, @forked_repo

    create(:commit_contribution,
           repository: @repo,
           user: @member,
           commit_count: 2,
           committed_date: Time.zone.today)

    @private_repo = create(:private_repository, owner: @member)
    create(:commit_contribution,
           repository: @private_repo,
           user: @member,
           commit_count: 3,
           committed_date: Time.zone.today)

    @authorizing_filter = cap_authorizing_filter
  end

  context "when user_repos_first = true" do
    test "should return matching user private/org repositories on top of the result if phrase not blank" do

      view = Branches::TargetRepositoryQuery.new(
        current_user: @member,
        phrase: "repo1",
        cap_filter: @authorizing_filter,
        user_repos_first: true
      )

      # create private user repo with a given name
      user_private_repo = create(:private_repository, owner: @member, name: "repo1")
      public_repo = create(:public_repository, owner: @org, name: "repo1")
      another_public_repo = create(:public_repository, owner: @org, name: "repo1-tmp")

      org_on_restricted_plan = create(:organization, plan: GitHub::Plan.gold, admin: @admin)
      org_on_restricted_plan.add_member(@member)
      org_on_restricted_plan_owned_repo = create(:public_repository, owner: org_on_restricted_plan)
      org_on_restricted_plan_owned_private_repo = create(:private_repository, owner: org_on_restricted_plan)

      # intentionally expecting org repo comes before user's own repo
      # because we have a reordering logic that should put user's repo on top
      repos_for_user_query = FakeRepoQuery.new([@org_owned_repo, user_private_repo])
      repos_query = FakeRepoQuery.new([public_repo, another_public_repo, user_private_repo])

      # @member is a member of [@org, org_on_restricted_plan]
      org_model_mock = Minitest::Mock.new
      org_model_mock.expect :pluck, [@org.login, org_on_restricted_plan.login], [:login]
      @member.expects(:organizations).returns(org_model_mock)

      user_org_subquery = "org:#{@org.login} org:#{org_on_restricted_plan.login}"
      # for user's own/org repos query
      Search::Queries::RepoQuery.expects(:new).with(
        phrase: "user:#{@member.login} #{user_org_subquery} in:name repo1",
        include_forks: true,
        current_user: @member,
        user_session: nil,
        sort: %w[updated desc]
      ).returns(repos_for_user_query)

      # for all repos query
      Search::Queries::RepoQuery.expects(:new).with(
        current_user: @member,
        user_session: nil,
        remote_ip: nil,
        phrase: "in:name repo1",
        include_forks: true
      ).returns(repos_query)

      repositories = view.repositories

      assert_equal 4, repositories.size
      assert_equal user_private_repo, repositories[0]
      assert_equal @org_owned_repo, repositories[1]
      assert_equal public_repo, repositories[2]
      assert_equal another_public_repo, repositories[3]

      assert_dogstats_distribution :at_least_one, "branches/target_repository_query/user-orgs-select-query.latency"
    end
  end

  test "should return user associated repositories ranked by contributions when phrase is blank" do
    view = Branches::TargetRepositoryQuery.new(
      current_user: @member,
      cap_filter: @authorizing_filter,
    )

    results = { @private_repo => { score: 10 }, @repo => { score: 5 }, @org_owned_repo => { score: 0 } }
    repositories = T.let(nil, T.nilable(T::Array[Repository]))
    Timecop.freeze do
      @member.expects(:ranked_contributed_repositories).with(
        include_issue_comments: true,
        exclude_owned: false,
        since: 30.days.ago,
      ).returns(results)
      repositories = view.repositories
    end

    repositories = T.must(repositories)
    assert_equal 3, repositories.size
    assert_equal @private_repo, repositories[0]
    assert_equal @repo, repositories[1]
    assert_equal @org_owned_repo, repositories[2]
  end

  test "passes the phrase and an `include_forks` option to the Search::Queries::RepoQuery" do
    phrase = "member"
    view = Branches::TargetRepositoryQuery.new(
      current_user: @forker,
      phrase: phrase,
      cap_filter: @authorizing_filter,
    )

    query = FakeRepoQuery.new([@repo])
    Search::Queries::RepoQuery.expects(:new).with(
      current_user: @forker,
      user_session: nil,
      remote_ip: nil,
      phrase: "in:name #{phrase}",
      include_forks: true
    ).returns(query)

    repositories = view.repositories
    assert_equal 1, repositories.size
    assert_equal @repo, repositories[0]
  end

  test "treats any text before the slash in phrase as the org/user name" do
    # ** Member owned repository **
    # Create a new private repo owned by the user
    private_repo = create(:private_repository, owner: @member)
    make_searchable private_repo

    member_view = Branches::TargetRepositoryQuery.new(
      current_user: @member,
      phrase: "#{@member}/",
      cap_filter: @authorizing_filter,
    )
    # Verify the updated phrase is used in the repo query
    query = FakeRepoQuery.new([private_repo, @repo])
    Search::Queries::RepoQuery.expects(:new).with(
      current_user: @member,
      user_session: nil,
      remote_ip: nil,
      phrase: "org:#{@member} user:#{@member}",
      include_forks: true
    ).returns(query)

    member_repositories = member_view.repositories
    assert_equal 2, member_repositories.size

    # ** Org owned repository **
    org_view = Branches::TargetRepositoryQuery.new(
      current_user: @member,
      phrase: "#{@org}/",
      cap_filter: @authorizing_filter,
    )
    query = FakeRepoQuery.new([@org_owned_repo, @org_owned_private_repo])
    Search::Queries::RepoQuery.expects(:new).with(
      current_user: @member,
      user_session: nil,
      remote_ip: nil,
      phrase: "org:#{@org} user:#{@org}",
      include_forks: true
    ).returns(query)

    org_repositories = org_view.repositories
    assert_equal 2, org_repositories.size
  end

  test "ensure searching for a particular repo within an org works" do
    view = Branches::TargetRepositoryQuery.new(current_user: @member, phrase: "#{@org}/#{@org_owned_private_repo}", cap_filter: @authorizing_filter)

    query = FakeRepoQuery.new([@org_owned_private_repo])
    Search::Queries::RepoQuery.expects(:new).with(
      current_user: @member,
      user_session: nil,
      remote_ip: nil,
      phrase: "org:#{@org} user:#{@org} in:name \"#{@org_owned_private_repo}\"",
      include_forks: true
    ).returns(query)

    org_repositories = view.repositories
    assert_equal 1, org_repositories.size
  end

  test "ensure special handling for repository with the same name of the organization" do
    view = Branches::TargetRepositoryQuery.new(current_user: @member, phrase: "awesome-org/awesome-org", cap_filter: @authorizing_filter)

    query = FakeRepoQuery.new([@org_owned_private_repo])
    Search::Queries::RepoQuery.expects(:new).with(
      current_user: @member,
      user_session: nil,
      remote_ip: nil,
      phrase: "org:awesome-org user:awesome-org in:name \"awesome-org/awesome-org\"",
      include_forks: true
    ).returns(query)

    org_repositories = view.repositories
    assert_equal 1, org_repositories.size
  end

  test "ensure selected_repository is first in list when phrase is blank" do
    @forked_repo.add_member(@member)
    view = Branches::TargetRepositoryQuery.new(current_user: @member, selected_repository: @forked_repo, cap_filter: @authorizing_filter)
    results = { @private_repo => { score: 10 }, @repo => { score: 5 }, @org_owned_repo => { score: 0 } }
    @member.expects(:ranked_contributed_repositories).returns(results)
    repositories = view.repositories
    assert_equal 4, repositories.size
    assert_equal @forked_repo, repositories[0]
  end

  test "ensure selected_repository is first in list when phrase is present" do
    @forked_repo.add_member(@member)
    phrase = "member"
    view = Branches::TargetRepositoryQuery.new(current_user: @member, phrase: phrase, selected_repository: @forked_repo, cap_filter: @authorizing_filter)

    query = FakeRepoQuery.new([@repo, @forked_repo])
    Search::Queries::RepoQuery.expects(:new).returns(query)

    repositories = view.repositories
    assert_equal 2, repositories.size
    assert_equal @forked_repo, repositories[0]
    assert_equal @repo, repositories[1]
  end

  context "SAML" do
    test "filters out SAML repos" do
      saml_org = create(:business_plus_org)
      saml_identity = create(:external_identity, org: saml_org)
      saml_user = saml_identity.user

      user_repo = create(:repository, owner: saml_user)

      saml_repo = create(:repository, owner: saml_org)
      saml_repo.add_member_without_validation_or_notifications(saml_user, action: :admin)

      cap_filter = cap_unauthorizing_filter([saml_repo])
      view = Branches::TargetRepositoryQuery.new(current_user: saml_user, phrase: "", cap_filter: cap_filter)

      repositories = view.repositories
      assert_equal 1, repositories.size
      assert_equal user_repo, repositories[0]
    end

    test "includes SAML repos when they have a valid session" do
      saml_org = create(:business_plus_org)
      saml_identity = create(:external_identity, org: saml_org)
      saml_user = saml_identity.user

      user_repo = create(:repository, owner: saml_user)

      saml_repo = create(:repository, owner: saml_org)
      saml_repo.add_member_without_validation_or_notifications(saml_user, action: :admin)

      view = Branches::TargetRepositoryQuery.new(current_user: saml_user, phrase: "", cap_filter: @authorizing_filter)

      repositories = view.repositories
      assert_equal 2, repositories.size
      assert_equal saml_repo, repositories[0]
      assert_equal user_repo, repositories[1]
    end
  end

  class FakeRepoQuery
    def initialize(repositories)
      @repositories = repositories
    end

    def execute
      self
    end

    def results
      @repositories.map { |repo| { "_model" => repo } }
    end
  end
end unless GitHub.enterprise?
