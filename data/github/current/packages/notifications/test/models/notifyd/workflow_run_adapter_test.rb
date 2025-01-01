# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class WorkflowRunAdapterTest < GitHub::TestCase

    setup do
      make_trusted_oauth_apps_owner

      @owner = create(:user)
      @member = create(:user)
      @org = create(:organization)
      @org.add_member(@owner)
      @org.add_member(@member)
      @repository = create(:repository, owner: @org)
      @team = @org.teams.create(name: "Approvers", privacy: :closed)
      @team.add_member(@owner)
      @team.add_member(@member)
      @env = create(:environment, repository: @repository)
      @team.add_repository(@repository, :admin)
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      @check_run = create(:check_run, :success, check_suite: check_suite)
      @gate = create(:gate, type: :manual_approval, environment: @env)
      @gate_request = GateRequest.create_or_update_gate_request(@gate, @check_run, "token", nil)
      @workflow_run = @gate_request.workflow_run
    end

    context "adapter tests for approval_requested operation", skip_enterprise: true do
      test "matches for gate request when it's closed" do
        assert @gate_request.closed?
        assert adapter(@workflow_run, operation: "approval_requested", gate_request_id: @gate_request.id).matches?
      end

      test "does not match if gate request is open" do
        @gate_request.update(state: :open)
        @gate_request.reload
        refute adapter(@workflow_run, operation: "approval_requested", gate_request_id: @gate_request.id).matches?
      end

      test "does not match if gate request is rejected" do
        @gate_request.update(state: :rejected)
        @gate_request.reload
        refute adapter(@workflow_run, operation: "approval_requested", gate_request_id: @gate_request.id).matches?
      end

      test "does not match if repository is missing" do
        make_trusted_oauth_apps_owner
        workflow_run = create(:check_suite_for_actions_app).workflow_run
        workflow_run.repository.delete
        workflow_run.reload
        refute adapter(workflow_run).matches?
      end

      test "#notify_feature_flag returns feature flag value" do
        assert_equal GitHub.flipper[:notifyd_enable_ci_activity], adapter(@workflow_run).notify_feature_flag
      end

      test "#notification_id returns check suite permalink without host" do
        GitHub.flipper[:notifyd_approval_requested_change_notification_id].disable
        assert_equal adapter(@workflow_run).notification_id, @workflow_run.permalink(include_host: false)
      end

      test "#notification_id returns workflow run message_id" do
        GitHub.flipper[:notifyd_approval_requested_change_notification_id].enable
        assert_equal adapter(@workflow_run, gate_request_id: @gate_request.id).notification_id, "/#{@repository.name_with_display_owner}/actions/runs/#{@workflow_run.id}/request/#{@gate_request.id}"
      end

      test "#repository_id returns check suite repostiory id" do
        assert_equal adapter(@workflow_run).repository_id, @workflow_run.repository.id
      end

      test "#authzd_attributes" do
        assert_equal adapter(@workflow_run).authzd_attributes, @workflow_run.permissions_wrapper.serialized_subject_attributes
      end

      context "#saml_enforcement" do
        test "for user without org" do
          make_trusted_oauth_apps_owner
          owner = create(:user)
          repository = create(:repository, owner: owner)
          env = create(:environment, repository: repository)
          check_suite = create(:check_suite_for_actions_app, repository: repository)
          check_run = create(:check_run, :success, check_suite: check_suite)
          gate = create(:gate, :approval, environment: env)
          workflow_run = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil).workflow_run
          assert_equal adapter(workflow_run).saml_enforcement, { skip_enforcement: true }
        end

        test "for user with org" do
          assert_equal adapter(@workflow_run).saml_enforcement, { organization_id: @org.id }
        end
      end

      test "#mobile_layout returns nil" do
        assert_nil adapter(@workflow_run).mobile_layout
      end

      test "#mobile_layout returns something on approval_requested" do
        refute_nil adapter(@workflow_run, { operation: "approval_requested", approver_ids: [@owner.id], actor_login: @owner.display_login }).mobile_layout
      end

      test "#email_layout returns correct address data" do
        layout = adapter(@workflow_run, { actor_login: "test_login" }).email_layout
        assert_equal layout.subject,  "Deployment review in #{@workflow_run.repository.name_with_owner}"
        assert_equal layout.to, Email::NoReplyAddress.new(name: @workflow_run.repository.name_with_owner, handle: @workflow_run.repository.to_s).to_s
        assert_nil layout.from
      end

      test "#email_layout returns correct multipart data" do
        layout = adapter(@workflow_run, { actor_login: "test_login" }).email_layout

        assert_equal layout.body.size, 2 # two parts

        # text part
        assert_equal layout.body[0].headers["Content-Type"], "text/plain; charset=UTF-8"
        refute_nil layout.body[0].headers["Content-Transfer-Encoding"]
        assert_match /workflow run/m, layout.body[0].content

        # html part
        assert_equal layout.body[1].headers["Content-Type"], "text/html; charset=UTF-8"
        refute_nil layout.body[1].headers["Content-Transfer-Encoding"]
        assert_match /<!DOCTYPE html PUBLIC/, layout.body[1].content
      end

      test "email layout headers" do
        layout = adapter(@workflow_run, { actor_login: "test_login" }).email_layout
        in_reply_to = "data"
        headers = Notifyd::EmailHeaders
          .new(@workflow_run, @workflow_run.repository, "test_login")
          .with_reply_to(Email::NoReplyAddress.new(name: @workflow_run.repository.name_with_owner, handle: @workflow_run.repository.to_s).to_s)
          .build
        assert_equal layout.headers.to_h["Message-ID"], headers[:"Message-ID"]
        assert_nil layout.headers.to_h["In-Reply-To"]
        assert_nil layout.headers.to_h["References"]
        assert_equal layout.headers.to_h["Precedence"], headers[:"Precedence"]
        assert_equal layout.headers.to_h["Return-Path"], headers[:"Return-Path"]
        assert_equal layout.headers.to_h["X-GitHub-Sender"], headers[:"X-GitHub-Sender"]
        assert_equal layout.headers.to_h["List-Id"], headers[:"List-Id"]
        assert_equal layout.headers.to_h["List-Archive"], headers[:"List-Archive"]
        assert_equal layout.headers.to_h["List-Post"], headers[:"List-Post"]
        assert_equal layout.headers.to_h["Reply-To"], headers[:"Reply-To"]
      end


      test "#related_topics returns correct data" do
        assert_equal [{ type: "repository", value: @workflow_run.repository.id.to_s }], adapter(@workflow_run).related_topics
      end

      test "#attributes returns correct data" do
        assert_equal [], adapter(@workflow_run).attributes
      end

      test "#explicit_recipients returns gate approvers" do
        expected = [
          {
            reason: "approval_requested",
            users: [@owner, @member]
          }
        ]
        explicit_recipients = adapter(@workflow_run, gate_id: @gate.id, approver_ids: [@owner.id, @member.id]).explicit_recipients
        assert_equal explicit_recipients.length, 1
        assert_equal explicit_recipients[0][:reason], "approval_requested"
        assert_equal explicit_recipients[0][:users].map(&:id).sort, [@owner.id, @member.id].sort
      end

      test "#owner_id should return repository owner id" do
        assert_equal adapter(@workflow_run).owner_id, @workflow_run.repository.owner.id
      end

      context "#owner_type" do
        test "for an organization is :organization" do
          assert_equal adapter(@workflow_run).owner_type, :organization
        end

        test "for a user is :user" do
          make_trusted_oauth_apps_owner
          owner = create(:user)
          repository = create(:repository, owner: owner)
          env = create(:environment, repository: repository)
          check_suite = create(:check_suite_for_actions_app, repository: repository)
          check_run = create(:check_run, :success, check_suite: check_suite)
          gate = create(:gate, :approval, environment: env)
          workflow_run = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil).workflow_run

          assert_equal adapter(workflow_run).owner_type, :user
        end
      end

      test "#trigger should return the trigger value from context" do
        assert_equal(adapter(@workflow_run, operation: "test").trigger, "test")
      end

      test "#feature_switches returns correct data" do
        expected = { notify_actor: true }
        assert_equal expected, adapter(@workflow_run).feature_switches
      end
    end

    private

    def adapter(subject, context = {})
      Notifyd::WorkflowRunAdapter.new(subject, context)
    end

  end
end
