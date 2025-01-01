# typed: true
# frozen_string_literal: true

require "test_helper"

class Search::Filters::OwnerRepoFilterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include Search::Filters

  fixtures do
    @org = create :organization
    @org_admin = @org.admins.first
    @org_member = create :user
    @org.add_member @org_member
    @org_repos = create_list(:private_repository, 2, owner: @org)
    @org_repos_ids = @org_repos.map(&:id)
    @private_personal_repo = create :private_repository, owner: @org_member
    @public_personal_repo = create :repository, owner: @org_member
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  context "builds the right type of filter" do
    test "builds an owner filter if user is org admin" do
      @quals[:org].must @org.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_admin, cap_filter: cap_authorizing_filter

      assert_equal({ terms: { owner_id: [@org.id] } }, filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 0, filter.repo_ids_size
      assert_equal "owner", filter.filter_type
      refute filter.accessible_repository?(@private_personal_repo)
      assert filter.accessible_repository?(@org_repos.first)
    end

    test "builds an owner filter if user is searching their own repos" do
      @quals[:owner].must @org_member.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_member, cap_filter: cap_authorizing_filter

      assert_equal({ terms: { owner_id: [@org_member.id] } }, filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 0, filter.repo_ids_size
      assert_equal "owner", filter.filter_type
      assert filter.accessible_repository?(@private_personal_repo)
    end

    test "builds an owner visibility filter if user is searching another user repos" do
      @quals[:owner].must @org_member.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_admin, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @org_member.id } },
        { term: { visibility: "public" } },
      ], filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 0, filter.repo_ids_size
      assert_equal "owner_visibility", filter.filter_type
      refute filter.accessible_repository?(@private_personal_repo)
    end

    test "builds a repository filter if the oauth token is missing the repo scope" do
      oauth = make_oauth @org_member, ["gist"]
      user = User.with_oauth_hashed_token(oauth.hashed_token)
      @quals[:owner].must @org_member.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: user, cap_filter: cap_authorizing_filter

      assert_equal({ term: { repo_id: @public_personal_repo.id } }, filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 1, filter.repo_ids_size
      assert_equal "repository", filter.filter_type
      refute filter.accessible_repository?(@private_personal_repo)
      assert filter.accessible_repository?(@public_personal_repo)
    end

    test "builds an owner visibility filter if user is member" do
      @quals[:org].must @org.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_member, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @org.id } },
        { bool: { should: [
          { terms: { repo_id: @org_repos_ids } },
          { terms: { visibility: %w[public internal] } },
        ] } }
      ], filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 2, filter.repo_ids_size
      assert_equal "owner_visibility", filter.filter_type
      refute filter.accessible_repository?(@private_personal_repo)
      assert filter.accessible_repository?(@org_repos.first)
    end

    test "builds a repository filter if many owners" do
      @quals[:user].must @org.login
      @quals[:user].must create(:user).login
      @quals[:user].must create(:user).login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_member, cap_filter: cap_authorizing_filter

      assert_equal({ terms: { repo_id: @org_repos_ids } }, filter.must)

      refute filter.blank?
      refute filter.global?
      assert_equal 2, filter.repo_ids_size
      assert_equal "repository", filter.filter_type
    end

    test "builds a classic repository filter if cannot apply optimization (no org:)" do
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_member, cap_filter: cap_authorizing_filter

      all_ids = @org_repos_ids + [@private_personal_repo.id]

      # Ensure order matches all_ids ordering
      filter.must[:bool][:should][1][:terms][:repo_id].sort!

      assert_equal({
        bool: { should: [
          { term: { public: true } },
          { terms: { repo_id: all_ids.sort } }]
        } }, filter.must)

      refute filter.blank?  # RepositoryFilter is never blank because it always generates at least public: true
      assert filter.global?
      assert_equal 3, filter.repo_ids_size
      assert_equal "repository", filter.filter_type
      assert filter.accessible_repository?(@private_personal_repo)
      assert filter.accessible_repository?(@org_repos.first)
    end

    test "builds a classic repository filter for negative org filter" do
      @quals[:org].must_not @org.login
      filter = OwnerRepoFilter.new qualifiers: @quals, current_user: @org_member, cap_filter: cap_authorizing_filter

      assert_equal({
        bool: { should: [
          { term: { public: true } },
          { term: { repo_id: @private_personal_repo.id } }]
        } }, filter.must)

      assert_equal({ terms: { repo_id: @org_repos_ids } }, filter.must_not)

      refute filter.blank?
      assert filter.global?
      assert_equal 1, filter.repo_ids_size
      assert_equal "repository", filter.filter_type
      assert filter.accessible_repository?(@private_personal_repo)
      refute filter.accessible_repository?(@org_repos.first)
    end
  end
end
