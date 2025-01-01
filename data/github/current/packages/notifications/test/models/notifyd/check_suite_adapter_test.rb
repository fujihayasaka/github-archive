# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class CheckSuiteAdapterTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @check_suite = create(:check_suite, :with_name, :failure, :with_push, pusher: @user)
    end

    context "#matches?" do
      test "matches for check suite event notification" do
        assert adapter(@check_suite).matches?
      end

      test "does not match if repository is missing" do
        @check_suite.repository.delete
        @check_suite.reload
        refute adapter(@check_suite).matches?
      end
    end

    test "#notify_feature_flag returns feature flag value" do
      assert_equal GitHub.flipper[:notifyd_enable_ci_activity], adapter(@check_suite).notify_feature_flag
    end

    test "#notification_id returns check suite permalink without host" do
      assert_equal adapter(@check_suite).notification_id, @check_suite.permalink(include_host: false)
    end

    test "#notification_id returns check suite permalink without host and the attempt" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :with_name, :failure, :with_push, pusher: @user)
      check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      check_suite.reload

      assert_equal adapter(check_suite).notification_id, "#{check_suite.permalink(include_host: false)}#2"
    end

    test "#repository_id returns check suite repostiory id" do
      assert_equal adapter(@check_suite).repository_id, @check_suite.repository.id
    end

    test "#authzd_attributes" do
      assert_equal adapter(@check_suite).authzd_attributes, @check_suite.permissions_wrapper.serialized_subject_attributes
    end

    context "#saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@check_suite).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        check_suite = create(:check_suite, :failure, :with_push, repository: repo)
        assert_equal adapter(check_suite).saml_enforcement, { organization_id: org.id }
      end
    end

    test "returns the layout with the feature enabled" do
      actor = create(:user)
      Flipper[:notifyd_mobile_push_ci_activity].enable(actor)

      refute_nil adapter(@check_suite, actor_id: actor.id).mobile_layout
    end

    test "#email_layout returns correct address data" do
      layout = adapter(@check_suite).email_layout
      assert_equal layout.subject, "[#{@check_suite.repository.name_with_owner}] Run failed: #{@check_suite.name} - #{@check_suite.head_branch} (#{@check_suite.short_head_sha})"
      assert_equal layout.from.name, @check_suite.creator.safe_profile_name
      assert_equal layout.to, "#{@check_suite.repository.name_with_owner} <#{@check_suite.repository}@noreply.github.com>"
      assert_equal layout.to, Email::NoReplyAddress.new(name: @check_suite.repository.name_with_owner, handle: @check_suite.repository.to_s).to_s
    end

    test "#email_layout returns correct multipart body" do
      layout = adapter(@check_suite).email_layout

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
      layout = adapter(@check_suite, { actor_login: "test_login", operation: "completed" }).email_layout
      headers = Notifyd::EmailHeaders
        .new(@check_suite, @check_suite.repository, "test_login")
        .with_reply_to(Email::NoReplyAddress.new(name: @check_suite.repository.name_with_owner, handle: @check_suite.repository.to_s).to_s)
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

    context "#email_title" do
      test "includes names of repo, workflow, and branch for regular (non-PR) runs" do
        layout = adapter(@check_suite).email_layout
        assert_equal layout.subject, "[#{@check_suite.repository.name_with_display_owner}] Run failed: #{@check_suite.name} - #{@check_suite.head_branch} (#{@check_suite.short_head_sha})"
        assert_equal layout.from.name, @check_suite.creator.safe_profile_name
      end

      test "refers to pull request when the head SHA and branch matches a PR" do
        make_trusted_oauth_apps_owner
        repo = create(:repository)
        pull_request_check_suite = create(
          :check_suite_for_actions_app,
          :failure,
          :with_push,
          repository: repo,
          head_repository: repo,
          head_branch: "wip-branch",
          event: "pull_request",
        )

        repo.heads.create(pull_request_check_suite.head_branch, pull_request_check_suite.head_sha, repo.owner)
        commit = repo.commits.find(pull_request_check_suite.head_sha)
        issue = create(:issue, repository: repo, title: "This code is awesome so we should merge it.")
        pr = create(
          :pull_request,
          :disable_disk_access,  # so that we don't have to search within a real repo
          issue: issue,
          head_sha: pull_request_check_suite.head_sha,
          head_ref: pull_request_check_suite.head_branch,
          head_repository: repo,
        )

        check_suite = pull_request_check_suite
        layout = adapter(check_suite).email_layout
        assert_equal layout.subject, "[#{pull_request_check_suite.repository.name_with_owner}] PR run failed: #{pull_request_check_suite.name} - #{pr.title} (#{pull_request_check_suite.short_head_sha})"
        assert_equal layout.from.name, pull_request_check_suite.creator.safe_profile_name
      end
    end

    test "#related_topics returns correct data" do
      assert_equal [{ type: "repository", value: @check_suite.repository.id.to_s }], adapter(@check_suite).related_topics
    end

    test "#attributes returns correct data" do
      assert_equal [{ name: "failed", value: "true" }], adapter(@check_suite).attributes
    end

    test "#explicit_recipients returns correct data" do
      expected = [
        {
          reason: "ci_activity",
          users: [@check_suite.creator]
        }
      ]
      assert_equal expected, adapter(@check_suite).explicit_recipients
    end

    test "#owner_id should return repository owner id" do
      assert_equal adapter(@check_suite).owner_id, @check_suite.repository.owner.id
    end

    context "#owner_type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        check_suite = create(:check_suite, :failure, :with_push, repository: repo)
        assert_equal adapter(check_suite).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@check_suite).owner_type, :user
      end
    end

    test "#trigger should return the trigger value from context" do
      assert_equal(adapter(@check_suite, operation: "test").trigger, "test")
    end

    test "#feature_switches returns correct data" do
      expected = { notify_actor: true, notify_subscribers: false }
      assert_equal expected, adapter(@check_suite).feature_switches
    end

    private

    def adapter(check_suite_notification, context = {})
      Notifyd::CheckSuiteAdapter.new(check_suite_notification, context)
    end
  end
end
