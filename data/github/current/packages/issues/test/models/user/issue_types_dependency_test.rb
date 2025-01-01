# typed: true
# frozen_string_literal: true

require "test_helper"

class UserIssueTypesDependencyTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    GitHub.flipper[:issue_types].enable
    @user = create(:user)
    @saml_org = create(:business_plus_organization)
    @external_identity = create :external_identity, org: @saml_org
    @saml_user = @external_identity.user
    @org = create(:organization).tap { |org| org.add_member(@user) }
    @org_2 = create(:organization).tap { |org| org.add_member(@user) }
    @repo = create(:repository, owner: @org)
    @other_member = create(:user)
    @org.add_member(@other_member)
    @collaborator = create(:collaborator, repository: @repo)
    @rando = create (:user), skip_enterprise_managed_user: true

    @org_issue_type = create :issue_type, name: "Must-have", owner: @org
    @org_2_issue_type = create :issue_type, name: "customer request", owner: @org_2, enabled: false
  end

  context "loads accessible_suggested_issue_type_names" do
    test "returns an empty array if user's orgs not visible to viewer" do
      assert_empty @user.accessible_suggested_issue_type_names(@rando, cap_unauthorizing_filter)
    end

    test "returns issue_types from user's visible repos if viewer is not user" do
      assert_equal 4,  @user.accessible_suggested_issue_type_names(@other_member, cap_authorizing_filter(@org)).count
    end

    test "returns all orgs' enabled issue types for org member if user is viewer" do
      assert_equal 4, @user.accessible_suggested_issue_type_names(@user, cap_authorizing_filter).count

      @org_2_issue_type.update enabled: true
      assert_equal 5, @user.accessible_suggested_issue_type_names(@user, cap_authorizing_filter).count
    end

    test "returns an empty array if user is viewer and not an org member", skip_with_all_emus: true do
      assert_empty @collaborator.accessible_suggested_issue_type_names(@collaborator, cap_authorizing_filter)
    end

    context "saml user" do
      test "returns all orgs' enabled issue types for org member" do
        cap_filter = cap_authorizing_filter([@saml_org])
        assert_equal 3, @saml_user.accessible_suggested_issue_type_names(@saml_user, cap_filter).count
      end

      test "returns an empty array if cap_filter not authorized" do
        cap_filter = cap_unauthorizing_filter([@saml_org])
        assert_empty @saml_user.accessible_suggested_issue_type_names(@saml_user, cap_filter)
      end
    end
  end
end
