# typed: true
# frozen_string_literal: true

require "test_helper"
require "feature_flag_helper"

class KnowledgeBases::Docset::HelpersTest < GitHub::TestCase
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

  context ".remove_unviewable_docset_source_repos" do
    test "return docset if source repos is nil" do
      docset = {
        ownerLogin: @user_accessible_org.login,
        ownerID: @user_accessible_org.id,
        ownerType: "organization",
        name: @user_accessible_org.name,
        description: nil,
        hardcoded: false,
        visibility: "private",
        id: "docset-id",
        createdByID: @user.id,
        sourceRepos: [],
        repos: [],
        iconHtml: "",
        visibleOutsideOrg: false,
        scopingQuery: nil
      }

      result = KnowledgeBases::Docset::Helpers.remove_unviewable_docset_source_repos(current_user: @user, cap_filter:, docset:)

      assert_equal docset, result
    end

    test "return docset with SSO authorized repos" do
      accessible_source_repo = T.cast({
        id: @accessible_org_repo.id,
        ownerID: @user_accessible_org.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      inaccessible_source_repo = T.cast({
        id: @inaccessible_org_repo.id,
        ownerID: @inaccessible_org_repo.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      invalid_source_repo = T.cast({
        id: 99999,
        ownerID: @accessible_org_repo.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      cap_stub = cap_authorizing_filter([@accessible_org_repo])

      docset = {
        ownerLogin: @user_accessible_org.login,
        ownerID: @user_accessible_org.id,
        ownerType: "organization",
        name: @user_accessible_org.name,
        description: nil,
        hardcoded: false,
        visibility: "private",
        id: "docset-id",
        createdByID: @user.id,
        sourceRepos: [accessible_source_repo, inaccessible_source_repo, invalid_source_repo],
        repos: [],
        iconHtml: "",
        visibleOutsideOrg: false,
        scopingQuery: nil
      }

      result = KnowledgeBases::Docset::Helpers.remove_unviewable_docset_source_repos(current_user: @user, cap_filter: cap_stub, docset:)

      assert_equal [accessible_source_repo], result[:sourceRepos]
    end

    test "return docset with SSO unauthorized repos removed" do
      accessible_source_repo = T.cast({
        id: @accessible_org_repo.id,
        ownerID: @user_accessible_org.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      inaccessible_source_repo = T.cast({
        id: @inaccessible_org_repo.id,
        ownerID: @inaccessible_org_repo.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      invalid_source_repo = T.cast({
        id: 99999,
        ownerID: @accessible_org_repo.id,
        paths: ["docs", "README.*"]
      }, KnowledgeBases::Docset::Helpers::SourceRepo)

      cap_stub = cap_unauthorizing_filter([@accessible_org_repo, @inaccessible_org_repo])

      docset = {
        ownerLogin: @user_accessible_org.login,
        ownerID: @user_accessible_org.id,
        ownerType: "organization",
        name: @user_accessible_org.name,
        description: nil,
        hardcoded: false,
        visibility: "private",
        id: "docset-id",
        createdByID: @user.id,
        sourceRepos: [accessible_source_repo, inaccessible_source_repo, invalid_source_repo],
        repos: [],
        iconHtml: "",
        visibleOutsideOrg: false,
        scopingQuery: nil
      }

      result = KnowledgeBases::Docset::Helpers.remove_unviewable_docset_source_repos(current_user: @user, cap_filter: cap_stub, docset: docset)

      assert_empty result[:sourceRepos]
    end
  end
end
