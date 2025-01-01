# typed: true
# frozen_string_literal: true

require "test_helper"

class HovercardsIssueLinksControllerHttpTest < GitHub::IntegrationTestCase

  include IssuesGraphTestHelpers

  fixtures do
    @staff_viewer = create(:staff_admin_user)
    @viewer = create(:user)
    @member = create(:user)
    @public_issue_repo = create(:repository)
    @private_issue_repo = create(:private_repository)
    create(:collaborator, collaborator: @member, repository: @private_issue_repo, action: :write)
    @private_issue = create(:issue, title: "Private issue", repository: @private_issue_repo)
    @public_issue = create(:issue, title: "Public issue", repository: @public_issue_repo)
    @private_issue_private_parent = create(:issue, title: "Private parent issue", repository: @private_issue_repo)
    create(:issue_link, source_issue: @private_issue_private_parent, target_issue: @private_issue)
    @private_issue_public_subtask = create(:issue, title: "Private subtask issue", repository: @private_issue_repo)
    create(:issue_link, source_issue: @private_issue, target_issue: @private_issue_public_subtask)
  end

  context "parents" do
    test "returns 406 if requesting as non-xhr" do
      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard"

      assert_response :not_acceptable
    end

    test "shows private issues on hovercard to users with access" do
      accessible_parent_issue = create(:issue, repository: @private_issue_repo)
      create(:issue_link, source_issue: accessible_parent_issue, target_issue: @private_issue)

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

      assert_response :success
      assert_select "[data-test-selector=issue-tracked-in-hovercard]", text: /#{accessible_parent_issue.title}/
    end

    test "shows issues-graph issues on hovercard to users with access" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_hierarchy_state)

      tracked_by = create(:issue, repository: @public_issue_repo)
      stub_tracking_issues(child: @private_issue, tracked_by: tracked_by)

      Timecop.freeze(@private_issue.updated_at + 5.seconds) do
        as @member
        get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true
      end

      assert_response :success
      assert_select "[data-test-selector=issue-tracked-in-hovercard]",
        text: /#{tracked_by.title}/
    end

    test "returns 404 for an inaccessible private issue" do
      as @viewer
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 for an inaccessible private issue when viewer is staff" do
      as @staff_viewer
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issues feature is disabled for the repo" do
      @private_issue_repo.update!(has_issues: false)
      disable_feature_flag(:tasklist_block, @private_issue_repo.owner)

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if owner doesn't exist" do
      as @viewer
      get "/nowhere-man/repo-doesnt-exist/issues/123/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if repo doesn't exist" do
      owner = create :user
      as @viewer
      get "/#{owner}/repo-doesnt-exist/issues/123/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issue doesn't exist" do
      nonexistent_issue_number = 123

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{nonexistent_issue_number}/tracked_in/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issue was deleted" do
      accessible_issue = create :issue, repository: @private_issue_repo
      number = accessible_issue.number
      DeletedIssue.delete_issue(accessible_issue, deleter: @member)

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{number}/tracked_in/hovercard", xhr: true

      assert_response 404
    end
  end

  context "tracking" do
    test "returns 406 if requesting as non-xhr" do
      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard"

      assert_response :not_acceptable
    end

    test "returns 404 for an inaccessible private issue" do
      as @viewer
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 for an inaccessible private issue when viewer is staff" do
      as @staff_viewer
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issues feature is disabled for the repo" do
      @private_issue_repo.update!(has_issues: false)
      disable_feature_flag(:tasklist_block, @private_issue_repo.owner)

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if owner doesn't exist" do
      as @viewer
      get "/nowhere-man/repo-doesnt-exist/issues/123/tracking/123/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if repo doesn't exist" do
      owner = create :user
      as @viewer
      get "/#{owner}/repo-doesnt-exist/issues/123/tracking/123/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issue doesn't exist" do
      nonexistent_issue_number = 123

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{nonexistent_issue_number}/tracking/#{@nonexistent_issue_number}/hovercard", xhr: true

      assert_response :not_found
    end

    test "returns 404 if issue was deleted" do
      accessible_issue = create :issue, repository: @private_issue_repo
      number = accessible_issue.number
      DeletedIssue.delete_issue(accessible_issue, deleter: @member)

      as @member
      get "/#{@private_issue_repo.name_with_display_owner}/issues/#{number}/tracking/#{number}/hovercard", xhr: true

      assert_response 404
    end

    test "renders tracked by title if valid issue provided" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_hierarchy_state)

      tracked_by = create(:issue, repository: @public_issue_repo)
      stub_tracking_issues(child: @private_issue, tracked_by: tracked_by)

      Timecop.freeze(@private_issue.updated_at + 5.seconds) do
        as @member
        get "/#{@public_issue_repo.name_with_display_owner}/issues/#{tracked_by.number}/tracking/#{@private_issue.id}/hovercard", xhr: true
      end

      assert_response :success
      assert_select "[data-test-selector=issue-tracking-hovercard-title]", text: /Tracks this issue in/
    end

    test "doesn't render tracked by title if tracking issue can't be found" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_hierarchy_state)

      tracked_by = create(:issue, repository: @public_issue_repo)
      stub_tracking_issues(child: @private_issue, tracked_by: tracked_by)

      @private_issue.destroy!
      Timecop.freeze(@private_issue.updated_at + 5.seconds) do
        as @member
        get "/#{@public_issue_repo.name_with_display_owner}/issues/#{tracked_by.number}/tracking/#{@private_issue.id}/hovercard", xhr: true
      end

      assert_response :success
      refute_select "[data-test-selector=issue-tracking-hovercard-title]", text: /Tracks this issue in/
    end

    test "doesn't render tracked by title if user can't view tracking issue" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_hierarchy_state)

      issue = create(:issue, repository: create(:private_repository))
      tracked_by = create(:issue, repository: @public_issue_repo)
      stub_tracking_issues(child: issue, tracked_by: tracked_by)

      Timecop.freeze(@private_issue.updated_at + 5.seconds) do
        as @member
        get "/#{@public_issue_repo.name_with_display_owner}/issues/#{tracked_by.number}/tracking/#{issue.id}/hovercard", xhr: true
      end

      assert_response :success
      refute_select "[data-test-selector=issue-tracking-hovercard-title]", text: /Tracks this issue in/
    end
  end
end

if GitHub.external_identity_session_enforcement_enabled?
  class HovercardsIssueLinksControllerActiveExternalIdentitySessionEnforcementHttpTest < GitHub::IntegrationTestCase
    include AuthenticationHelpers::SAML

    fixtures do
      @saml_org = create(:business_plus_org)
      @saml_identity = create(:external_identity, org: @saml_org)
      @saml_user = @saml_identity.user
      @saml_org.update_member(@saml_user, action: :admin)
      @sso_org_private_repo = create(:private_repository, owner: @saml_org)
      @private_issue = create(:issue, repository: @sso_org_private_repo)
      @sso_org_public_repo = create(:repository, owner: @saml_org)
      @public_issue = create(:issue, repository: @sso_org_public_repo)
    end

    context "tracked_in" do
      test "unauthenticated privileged user, links to single sign-on for protected org when no active external identity session" do
        current_path = "some/issue/123123"

        as @saml_user, create_external_identity_session: false
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true

        assert_response :unauthorized
      end

      test "authenticated privileged user, does not link to single sign-on for protected org when active external identity session" do
        as @saml_user
        session = @saml_user.sessions.last
        create(:external_identity_session, user_session: session,
                                                  external_identity: @saml_identity)
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response :ok

        if GitHub.flipper[:tasklist_tracked_by_redesign].enabled?
          assert_select "[data-test-selector=issue-tracked-in-hovercard-title]", text: /Listed in/
        else
          assert_select "[data-test-selector=issue-tracked-in-hovercard]", text: /Listed in/
        end
      end

      test "unprivileged user, does not link to single sign-on for protected org when active external identity session" do
        as @viewer
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response_not_found
      end

      test "anon user, does not link to single sign-on for protected org when active external identity session" do
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response_not_found
      end

      # no public repos in EMU mode
      context "on a public repo", skip_with_all_emus: true do
        test "unauthenticated privileged user, does not links to single sign-on for protected org when no active external identity session" do
          current_path = "some/issue/123123"

          as @saml_user
          get "/#{@sso_org_public_repo.name_with_display_owner}/issues/#{@public_issue.number}/subtasks/parents/hovercard?current_path=#{current_path}", xhr: true

          assert_response :not_found
        end

        test "authenticated privileged user, does not link to single sign-on for protected org when active external identity session" do
          as @saml_user
          session = @saml_user.sessions.last
          create(:external_identity_session, user_session: session,
                external_identity: @saml_identity)
          get "/#{@sso_org_public_repo.name_with_display_owner}/issues/#{@public_issue.number}/subtasks/parents/hovercard", xhr: true

          assert_response :not_found
        end
      end
    end

    context "tracking" do
      test "unauthenticated privileged user, links to single sign-on for protected org when no active external identity session" do
        current_path = "some/issue/123123"

        as @saml_user, create_external_identity_session: false
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true

        assert_response :unauthorized
      end

      test "authenticated privileged user, does not link to single sign-on for protected org when active external identity session" do
        as @saml_user
        session = @saml_user.sessions.last
        create(:external_identity_session, user_session: session, external_identity: @saml_identity)
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response :ok

        assert_select "[data-test-selector=issue-hovercard]", text: /#{@private_issue.title}/
      end

      test "unprivileged user, does not link to single sign-on for protected org when active external identity session" do
        as @viewer
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response_not_found
      end

      test "anon user, does not link to single sign-on for protected org when active external identity session" do
        get "/#{@sso_org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response_not_found
      end

      # no public repos in EMU mode
      context "on a public repo", skip_with_all_emus: true do
        test "unauthenticated privileged user, does not links to single sign-on for protected org when no active external identity session" do
          current_path = "some/issue/123123"

          as @saml_user
          get "/#{@sso_org_public_repo.name_with_display_owner}/issues/#{@public_issue.number}/tracking/#{@public_issue.number}/t/hovercard?current_path=#{current_path}", xhr: true

          assert_response :not_found
        end

        test "authenticated privileged user, does not link to single sign-on for protected org when active external identity session" do
          as @saml_user
          session = @saml_user.sessions.last
          create(:external_identity_session, user_session: session,
                external_identity: @saml_identity)
          get "/#{@sso_org_public_repo.name_with_display_owner}/issues/#{@public_issue.number}/tracking/#{@public_issue.number}/t/hovercard", xhr: true

          assert_response :not_found
        end
      end
    end
  end
end

if GitHub.ip_allowlists_available?
  class HovercardsIssueLinksControllerIpAllowListEnforcementHttpTest < GitHub::IntegrationTestCase

    fixtures do
      @rando = create :user, skip_enterprise_managed_user: true
      @user = create :user
      @org = create :business_plus_org, admin: @user
      @org.enable_ip_allowlist actor: @user
      create :ip_allowlist_entry, owner: @org, allow_list_value: "10.10.10.0/24"
      @org_private_repo = create(:private_repository, owner: @org)
      @private_issue = create(:issue, repository: @org_private_repo)
      @org_public_repo = create(:repository, owner: @org)
      @public_issue = create(:issue, repository: @org_public_repo)
    end

    context "tracked_in" do
      test "unauthenticated privileged user, shows hint for protected org without an allowed IP" do
        current_path = "some/issue/123123"

        as @user
        request_env["REMOTE_ADDR"] = "1.2.3.4"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true

        assert_response :forbidden
      end

      test "authenticated privileged user, does not show hint for protected org with an allowed IP" do
        as @user
        request_env["REMOTE_ADDR"] = "10.10.10.10"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response :ok

        if GitHub.flipper[:tasklist_tracked_by_redesign].enabled?
          assert_select "[data-test-selector=issue-tracked-in-hovercard-title]", text: /Listed in/
        else
          assert_select "[data-test-selector=issue-tracked-in-hovercard]", text: /Listed in/
        end
      end

      test "unprivileged user, 404s for protected org" do
        as @rando
        request_env["REMOTE_ADDR"] = "10.10.10.10"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response_not_found
      end

      test "anonymous user, 404s for protected org" do
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard", xhr: true

        assert_response_not_found
      end
    end

    context "tracking" do
      test "unauthenticated privileged user, shows hint for protected org without an allowed IP" do
        current_path = "some/issue/123123"

        as @user
        request_env["REMOTE_ADDR"] = "1.2.3.4"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true

        assert_response :forbidden
      end

      test "authenticated privileged user, does not show hint for protected org with an allowed IP" do
        as @user
        request_env["REMOTE_ADDR"] = "10.10.10.10"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response :ok
      end

      test "unprivileged user, 404s for protected org" do
        as @rando
        request_env["REMOTE_ADDR"] = "10.10.10.10"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response_not_found
      end

      test "anonymous user, 404s for protected org" do
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard", xhr: true

        assert_response_not_found
      end
    end
  end

  class HovercardsIssueLinksController2FAEnforcementHttpTest < GitHub::IntegrationTestCase
    # 2FA does not apply to enterprise managed users as 2FA is enforced by the external provider NOT github
    skip_with_all_emus

    fixtures do
      @member_without_2fa = create :user
      @org = create(:two_factor_credential_org)
      @org.add_member(@member_without_2fa)

      @org_private_repo = create(:private_repository, owner: @org)
      @private_issue = create(:issue, repository: @org_private_repo)
    end

    context "tracked_in" do
      test "user without 2FA is denied access and prompted to set 2FA when request is XHR" do
        current_path = "some/issue/123123"

        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true

        assert_response :forbidden
      end

      test "user with 2FA is allowed" do
        current_path = "some/issue/123123"

        make_two_factor_credential(@member_without_2fa)
        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true

        assert_response :ok
      end

      test "user without 2FA is forbidden access when request is not XHR" do
        current_path = "some/issue/123123"

        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}"

        assert_response :forbidden
      end

      test "404 for anonymous user on protected org resource" do
        current_path = "some/issue/123123"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true
        assert_response :not_found
      end

      test "404 for non member user on protected org resource" do
        current_path = "some/issue/123123"
        as @rando
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracked_in/hovercard?current_path=#{current_path}", xhr: true
        assert_response :not_found
      end
    end

    context "tracking" do
      test "user without 2FA is denied access and prompted to set 2FA when request is XHR" do
        current_path = "some/issue/123123"

        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true

        assert_response :forbidden
      end

      test "user with 2FA is allowed" do
        current_path = "some/issue/123123"

        make_two_factor_credential(@member_without_2fa)
        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true

        assert_response :ok
      end

      test "user without 2FA is forbidden access when request is not XHR" do
        current_path = "some/issue/123123"

        as @member_without_2fa
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}"

        assert_response :forbidden
      end

      test "404 for anonymous user on protected org resource" do
        current_path = "some/issue/123123"
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true
        assert_response :not_found
      end

      test "404 for non member user on protected org resource" do
        current_path = "some/issue/123123"
        as @rando
        get "/#{@org_private_repo.name_with_display_owner}/issues/#{@private_issue.number}/tracking/#{@private_issue.number}/hovercard?current_path=#{current_path}", xhr: true
        assert_response :not_found
      end
    end
  end
end
