# typed: true
# frozen_string_literal: true

require "test_helper"

class Search::Filters::OwnerVisibilityFilterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include Search::Filters

  fixtures do
    @org = create(:organization, login: "an-org")
    @org_repos = create_list(:private_repository, 2, owner: @org)
    @org_repos_ids = @org_repos.map(&:id)
    @org_admin = @org.admins.first
    @org_member = create :user
    @org.add_member(@org_member)

    @biz_org = create(:enterprise_linked_organization)
    # Prevent new private repos to be visible to every org member
    @biz_org.update_default_repository_permission :none, actor: @biz_org.admins.first
    @biz = @biz_org.business
    @biz_owner = @biz.owners.first
    @biz_member = create(:user)
    @biz_org.add_member(@biz_member)
    @biz_internal_repo = create(:internal_repository, owner: @biz_org)
    @biz_private_repo = create(:private_repository, owner: @biz_org)
    @biz_private_repo.add_member(@biz_member)
  end

  context "queries constrained by visibility" do
    context "valid user - non-biz-org" do
      test "builds an org filter if query requests public" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("public"), current_user: @org_admin, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @org.id } },
          { term: { visibility: "public" } },
        ], filter.must)

        refute filter.blank?
        refute filter.global?
        assert_equal 0, filter.repo_ids_size
      end

      test "builds a blank filter if the org has no internal but the query requests internal" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("internal"), current_user: @org_admin, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @org.id } },
          { term: { visibility: "internal" } },
        ], filter.must)
      end

      test "builds an org filter when the query requests private" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("private"), current_user: @org_admin, cap_filter: cap_authorizing_filter

        assert_equal({ terms: { repo_id: @org_repos_ids } }, filter.must)
        assert_equal 2, filter.repo_ids_size
      end

      test "builds a public filter if the user does not belong to the org" do
        external_user = create :user
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: external_user, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @org.id } },
          { term: { visibility: "public" } },
        ], filter.must)
      end
    end

    context "valid user - biz-org" do
      test "builds an org filter user-limited to public" do
        filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter("public"), current_user: @biz_member, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @biz_org.id } },
          { term: { visibility: "public" } },
        ], filter.must)
      end

      test "builds an org filter user-limited to internal" do
        filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter("internal"), current_user: @biz_member, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @biz_org.id } },
          { term: { visibility: "internal" } },
        ], filter.must)
      end

      test "builds a repos filter user-limited to private" do
        # The internal repo with direct access must be ignored because the query is visibility:private
        @biz_internal_repo.add_member(@biz_member)
        filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter("private"), current_user: @biz_member, cap_filter: cap_authorizing_filter

        assert_equal({ term: { repo_id: @biz_private_repo.id } }, filter.must)
      end

      test "builds an org filter if visibility filter is negative" do
        not_filter = build_visibility_filter visibility_not: "internal"
        filter = OwnerVisibilityFilter.new @biz_org, not_filter, current_user: @biz_member, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @biz_org.id } },
          { bool: { should: [
            { term: { repo_id: @biz_private_repo.id } },
            { terms: { visibility: %w[public internal] } },
          ] } },
        ], filter.must)
        assert_equal 1, filter.repo_ids_size
      end
    end

    context "anonymous user" do
      test "builds an org public filter if the query requests public" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("public"), current_user: nil, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @org.id } },
          { term: { visibility: "public" } },
        ], filter.must)
      end

      test "builds a blank filter if the query requests internal" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("internal"), current_user: nil, cap_filter: cap_authorizing_filter

        assert_equal({ terms: { repo_id: [] } }, filter.must)
        assert_equal 0, filter.repo_ids_size
      end

      test "builds a blank filter if the query requests private" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter("private"), current_user: nil, cap_filter: cap_authorizing_filter

        assert_equal({ terms: { repo_id: [] } }, filter.must)
      end

      test "builds an org public filter if the query doesn't filter by visibility" do
        filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: nil, cap_filter: cap_authorizing_filter

        assert_equal([
          { term: { owner_id: @org.id } },
          { term: { visibility: "public" } },
        ], filter.must)
      end
    end
  end

  context "queries without visibility qualifier" do
    test "builds an org filter for valid user - non-biz-org" do
      # Note admin does make a difference as the owner_id optimization lives at RepoQuery.
      # OwnerVisibilityFilter generates the 3 scopes for admins too: public/internal/private.
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: @org_admin, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @org.id } },
        { bool: { should: [
          { terms: { repo_id: @org_repos_ids } },
          { terms: { visibility: %w(public internal) } },
        ] } },
      ], filter.must)
    end

    test "builds a restricted org filter without internal repos for valid user - biz-org without SAML access" do
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: @biz_member, cap_filter: cap_unauthorizing_filter(@biz)

      assert_equal([
        { term: { owner_id: @biz_org.id } },
        { bool: { should: [
          { term: { repo_id: @biz_private_repo.id } },
          { term: { visibility: "public" } },
        ] } },
        ], filter.must)
    end

    test "builds an org filter with direct-granted internal repos even if no SAML access" do
      @biz_internal_repo.add_member(@biz_member)
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: @biz_member, cap_filter: cap_unauthorizing_filter(@biz)

      assert_equal([
        { term: { owner_id: @biz_org.id } },
        { bool: { should: [
          { terms: { repo_id: [@biz_internal_repo.id, @biz_private_repo.id] } },
          { term: { visibility: "public" } },
        ] } },
        ], filter.must)
      assert_equal 2, filter.repo_ids_size
    end

    test "builds an org filter with direct-granted internal repos even if no SAML access when query includes internal only" do
      @biz_internal_repo.add_member(@biz_member)
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter("internal"), current_user: @biz_member, cap_filter: cap_unauthorizing_filter(@biz)

      assert_equal({ term: { repo_id: @biz_internal_repo.id } }, filter.must)
    end

    test "builds an org filter for an external collaborator" do
      non_member = create :user
      @biz_internal_repo.add_member(non_member)
      @biz_private_repo.add_member(non_member)
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: non_member, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @biz_org.id } },
        { bool: { should: [
          { terms: { repo_id: [@biz_internal_repo.id, @biz_private_repo.id] } },
          { term: { visibility: "public" } },
        ] } },
      ], filter.must)
      assert_equal 2, filter.repo_ids_size
    end

    test "builds an org filter for an external collaborator without internal IDs if they are filtered out in the query" do
      non_member = create :user
      @biz_internal_repo.add_member(non_member)
      @biz_private_repo.add_member(non_member)
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter("private"), current_user: non_member, cap_filter: cap_authorizing_filter

      assert_equal({ term: { repo_id: @biz_private_repo.id } }, filter.must)
    end

    test "builds an org filter for valid user - biz-org" do
      # This internal id won't be added to repo_id because we're already including every internal repo in the query
      @biz_internal_repo.add_member(@biz_member)
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: @biz_member, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @biz_org.id } },
        { bool: { should: [
          { term: { repo_id: @biz_private_repo.id } },
          { terms: { visibility: %w[public internal] } },
        ] } },
      ], filter.must)
    end

    test "builds an org filter for anonymous user" do
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: nil, cap_filter: cap_authorizing_filter

      assert_equal([
        { term: { owner_id: @org.id } },
        { term: { visibility: "public" } },
      ], filter.must)
    end
  end

  context "GitHub Apps" do
    test "applies org OAuth app policy to accessible repositories" do
      oauth_user = oauthed_user(@org_admin, %w(repo))

      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: oauth_user, cap_filter: cap_authorizing_filter
      assert_equal([
        { term: { owner_id: @org.id } },
        { bool: { should: [
          { terms: { repo_id: @org_repos_ids } },
          { terms: { visibility: %w(public internal) } },
        ] } },
      ], filter.must)

      @org.enable_oauth_application_restrictions
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: oauth_user, cap_filter: cap_authorizing_filter
      assert_equal([
        { term: { owner_id: @org.id } },
          { terms: { visibility: %w(public internal) } },
      ], filter.must)
    end if GitHub.oauth_application_policies_enabled?

    test "excludes private repositories for the current_user where the resource is inaccessible" do
      integration = create :integration

      grant = integration.grant @org_admin
      @org_admin.oauth_access = grant

      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: @org_admin, cap_filter: cap_authorizing_filter
      assert_equal([
        { term: { owner_id: @org.id } },
        { terms: { visibility: %w(public internal) } },
      ], filter.must)
    end

    test "excludes private repositories for an organization when the installation doesn't have access" do
      accessible_private_repo = @org_repos.first
      inaccessible_private_repo = @org_repos.second

      assert accessible_private_repo.readable_by?(@org_admin)
      assert inaccessible_private_repo.readable_by?(@org_admin)

      installation = make_integration_installation(repository: accessible_private_repo, permissions: { "metadata" => :read })

      assert accessible_private_repo.resources.metadata.readable_by?(installation)
      refute inaccessible_private_repo.resources.metadata.readable_by?(installation)

      grant = installation.integration.grant(@org_admin)
      @org_admin.oauth_access = grant

      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: @org_admin, cap_filter: cap_authorizing_filter
      assert_equal([
        { term: { owner_id: @org.id } },
        { bool: { should: [
          { term: { repo_id: accessible_private_repo.id } },
          { terms: { visibility: %w(public internal) } },
        ] } },
      ], filter.must)
    end
  end

  context "accessible_repository?" do
    test "returns false for a private repository - anonymous" do
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: nil, cap_filter: cap_authorizing_filter
      refute filter.accessible_repository? @org_repos.first
    end

    test "returns false for a private repository - external user" do
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: create(:user), cap_filter: cap_authorizing_filter
      refute filter.accessible_repository? @org_repos.first
    end

    test "returns true for a private repository - member" do
      filter = OwnerVisibilityFilter.new @org, build_visibility_filter, current_user: @org_member, cap_filter: cap_authorizing_filter
      assert filter.accessible_repository? @org_repos.first
    end

    test "returns false for enterprise repositories - anonymous" do
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: nil, cap_filter: cap_authorizing_filter
      refute filter.accessible_repository? @biz_internal_repo
      refute filter.accessible_repository? @biz_private_repo
    end

    test "returns false for enterprise repositories - external user" do
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: create(:user), cap_filter: cap_authorizing_filter
      refute filter.accessible_repository? @biz_internal_repo
      refute filter.accessible_repository? @biz_private_repo
    end

    test "returns true for enterprise repositories - member" do
      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: @biz_member, cap_filter: cap_authorizing_filter
      assert filter.accessible_repository? @biz_internal_repo
      assert filter.accessible_repository? @biz_private_repo
    end

    test "returns true for an installed bot only for the authorized repos" do
      installation = make_integration_installation(repository: @biz_private_repo, permissions: { "metadata" => :read })

      filter = OwnerVisibilityFilter.new @biz_org, build_visibility_filter, current_user: installation.bot, cap_filter: cap_authorizing_filter
      refute filter.accessible_repository? @biz_internal_repo
      assert filter.accessible_repository? @biz_private_repo
    end
  end

  def build_visibility_filter(visibility = nil, visibility_not: nil)
    qualifiers = Search::ParsedQuery.qualifiers
    qualifiers[:visibility].must visibility if visibility
    qualifiers[:visibility].must_not visibility_not if visibility_not
    EnumeratedTermFilter.new(field: :visibility, keys: [:visibility], qualifiers:)
  end

  def oauthed_user(user = create(:user), scopes = [])
    User.with_oauth_hashed_token(make_oauth(user, scopes).hashed_token)
  end
end
