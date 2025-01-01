# typed: true
# frozen_string_literal: true

require "test_helper"
require "feature_flag_helper"

class KnowledgeBases::PublicTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper # for cap_authorizing_filter, cap_unauthorizing_filter

  fixtures do
    @user_accessible_org = create(:copilot_feature_enabled_enterprise_organization)
    @user_inaccessible_org = create(:copilot_feature_enabled_enterprise_organization)
    @user = create :user
    @second_user = create :user
    @user_accessible_org.add_member(@user)
    @user_accessible_org.add_member(@second_user)
    @accessible_org_repo = create(:repository, owner: @user_accessible_org)
    @accessible_org_repo.add_member(@user)
    @inaccessible_org_repo = create(:repository, owner: @user_inaccessible_org)
  end

  setup do
    GitHub.stubs(:copilot_enabled?).returns(true)
    # Otherwise TEST_ALL_FEATURES will turn this on and all orgs will have Copilot Enterprise
    disable_feature_flag(:copilot_for_enterprise)
  end

  def cap_filter
    return @cap_filter_instance if @cap_filter_instance
    @cap_filter_instance = cap_unauthorizing_filter
  end

  def cap_filter=(cap_filter_instance)
    @cap_filter_instance = cap_filter_instance
  end

  # We do not need to filter out orgs that you have not SSO'd into because we reveal the org name and avatar when you
  # are not SSO'd in other parts of dotcom by design: https://github.com/github/copilot-core-productivity/issues/1239#issuecomment-1971324212
  context ".administrated_copilot_enterprise_organizations" do
    test "returns org that has Copilot Enterprise, that user can administer, has no trade restrictions" do
      copilot_enterprise_org = create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise, admin: @user)

      orgs = KnowledgeBases::Public.administrated_copilot_enterprise_organizations(@user)

      assert_equal [{
        id: copilot_enterprise_org.id,
        name: copilot_enterprise_org.name,
        login: copilot_enterprise_org.display_login,
        avatarUrl: copilot_enterprise_org.primary_avatar_url
      }], orgs
    end

    test "filters out non-adminable org" do
      copilot_enterprise_org_not_adminable = create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise)
      copilot_enterprise_org_not_adminable.add_member(@user)

      orgs = KnowledgeBases::Public.administrated_copilot_enterprise_organizations(@user)

      assert_empty orgs
    end

    test "filters out org with trade restrictions" do
      create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise, admin: @user)
      Organization.any_instance.expects(:has_sdn_new_org_with_free_plan_restriction?).at_least_once.returns(true)

      orgs = KnowledgeBases::Public.administrated_copilot_enterprise_organizations(@user)

      assert_empty orgs
    end

    test "filters out Copilot Business org" do
      copilot_business_org = create(:copilot_for_business_enabled_organization, admin: @user)
      # EMU test mode sets the plan to Enterprise so we need to manually set it back to business
      T.must(Copilot::Organization.new(copilot_business_org).copilot_business).copilot_plan_business!

      orgs = KnowledgeBases::Public.administrated_copilot_enterprise_organizations(@user)

      assert_empty orgs

    end
  end

  context ".filter_visible_docsets?" do
    test "removes knowledge bases that aren't SSO authorized", skip_enterprise: true do
      cap_stub = cap_unauthorizing_filter
      knowledge_bases = [
        { id: "docset-id", name: @user_accessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_accessible_org.id, ownerLogin: @user_accessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
      ]
      filtered = KnowledgeBases::Public.filter_visible_docsets(current_user: @user, cap_filter: cap_stub, docsets: knowledge_bases)
      assert_equal([], filtered)
    end

    test "keeps knowledge bases that are SSO authorized", skip_enterprise: true do
      cap_stub = cap_authorizing_filter
      knowledge_bases = [
        { id: "docset-id", name: @user_accessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_accessible_org.id, ownerLogin: @user_accessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
      ]
      filtered = KnowledgeBases::Public.filter_visible_docsets(current_user: @user, cap_filter: cap_stub, docsets: knowledge_bases)
      assert_equal(knowledge_bases, filtered)
    end

    context "when the user's org has knowledge bases created" do
      test "filters out inaccessible knowledge bases", skip_enterprise: true do
        # Test does not stub cap filter
        knowledge_bases = [
          { id: "docset-id-1", name: @user_accessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_accessible_org.id, ownerLogin: @user_accessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
          { id: "docset-id-2", name: @user_inaccessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_inaccessible_org.id, ownerLogin: @user_inaccessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
        ]
        filtered = KnowledgeBases::Public.filter_visible_docsets(current_user: @user, cap_filter: cap_filter, docsets: knowledge_bases)
        assert_equal([], filtered)
      end
    end

    context "when there are core knowledge bases not owned by the user's org" do
      test "allows the user to see core knowledge bases" do
        knowledge_bases = [
          { id: "docset-id-1", name: @user_inaccessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_inaccessible_org.id, ownerLogin: @user_inaccessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
          { id: "docset-id-2", name: @user_inaccessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_inaccessible_org.id, ownerLogin: @user_inaccessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "core", visibleOutsideOrg: nil },
          { id: "docset-id-3", name: @user_inaccessible_org.name + "2", description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user_inaccessible_org.id, ownerLogin: @user_inaccessible_org.login, ownerType: "organization", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "core", visibleOutsideOrg: nil },
        ]
        filtered = KnowledgeBases::Public.filter_visible_docsets(current_user: @user, cap_filter:, docsets: knowledge_bases)
        assert_equal([knowledge_bases[1], knowledge_bases[2]], filtered)
      end
    end

    context "when the knowledge base was created by the user" do
      test "filters out inaccessible knowledge bases", skip_enterprise: true do
        knowledge_bases = [
          { id: "docset-id-1", name: @user_accessible_org.name, description: nil, createdByID: @user.id, hardcoded: nil, ownerID: @user.id, ownerLogin: @user.login, ownerType: "user", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
          { id: "docset-id-2", name: @user_accessible_org.name + "2", description: nil, createdByID: @second_user.id, hardcoded: nil, ownerID: @second_user.id, ownerLogin: @second_user.login, ownerType: "user", scopingQuery: nil, sourceRepos: nil, repos: [], iconHtml: nil, visibility: "private", visibleOutsideOrg: nil },
        ]
        filtered = KnowledgeBases::Public.filter_visible_docsets(current_user: @user, cap_filter:, docsets: knowledge_bases)
        assert_equal([knowledge_bases[0]], filtered)
      end
    end
  end
end
