# coding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class AlertsServiceTest < GitHub::TestCase
  include SecretScanning::Errors
  include DogstatsTestHelpers

  ResponseMock = Struct.new(:data, :error)
  ResponseErrorMock = Struct.new(:msg)

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, login: "repoadmin", email: "repoadmin@github.com")
    @org = create(:business_plus_organization, name: "org", admin: @user)
    @repo = create(:private_repository, owner: @org)
    @emu_repo = create(:repository, force_user_owned: true, owner: @user)

    @alerts_service = SecretScanning::Services::AlertsService.new
  end

  context "#get_alert" do
    test "invokes get token rpc call" do
      disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token).with(equals(get_token_request)).once

      @alerts_service.get_alert(@repo, @user, 1, 1)
    end

    test "invokes wrap token rpc call if token is valid" do
      disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK)
      token = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "foo.txt"),
        id: 1,
        label: "token_api",
        number: 1,
        repository_id: @repo.id,
        slug: "token_api",
        token_type: "TOKEN_API"
      )

      data = GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse.new(token: token)
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token).with(equals(get_token_request)).returns(
        ResponseMock.new(
          data: data
        )
      )

      expected_wrapped_token = GitHub::TokenScanning::Service::Token.new(token, @repo, data)

      GitHub::TokenScanning::Service::Client.expects(:wrap_token).with(token, @repo, data).once.returns(expected_wrapped_token)

      @alerts_service.get_alert(@repo, @user, 1, 1)
    end
  end

  context "#resolve_token" do
    test "resolves alert with valid resolution and no dismissal comment" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED)

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })
    end

    test "resolves alert with valid resolution and a dismissal comment" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("false_positive").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE).once

      dismissal_comment = "This alert isn't true"
      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE, dismissal_comment)

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "false_positive", dismissal_comment: dismissal_comment, numbers_to_slugs: { 1 => "test_slug" })
    end

    test "dismissal comment with non UTF-8 characters is normalized before resolution" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("false_positive").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE).once
      dismissal_comment = "κόσμε"
      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE, dismissal_comment)

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "false_positive", dismissal_comment: dismissal_comment, numbers_to_slugs: { 1 => "test_slug" })
    end

    test "dismissal comment is not nil if alert is reopened" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("reopened").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED, "this comment should not be nil")

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "reopened", dismissal_comment: "this comment should not be nil", numbers_to_slugs: { 1 => "test_slug" })

    end

    test "returns unprocessable entity if resolution is invalid" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("invalid").returns(nil).once
      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).never

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "invalid", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal  UnprocessableEntity, response.class
    end

    test "returns timeout error when response is nil" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED)

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(request)).returns(nil)

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "timeout when resolving token", response.message
    end

    test "returns not found error when the response is not found" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED)

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: Twirp::Error.not_found("could not find something")))

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal NotFoundByService, response.class
      assert_equal "could not find something", response.message
    end

    test "returns error with message when present" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED)

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: Twirp::Error.internal("something went wrong")))

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "something went wrong", response.message
    end

    test "audit entry for emu" do
      GitHub.stubs(:instrument).with("cache_get.spokes_adapter", any_parameters)
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("used_in_tests").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS).once
      request = {
        repository_id: @emu_repo.id,
        token_numbers: [1],
        resolver_id: @user.id,
        resolution: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
        default_branch_name: @repo.default_branch,
        feature_flags: [],
        resolution_comment: nil
      }

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil))

      GitHub.expects(:instrument).with(
        "secret_scanning_alert.resolve",
        {
          user: @user,
          repo: @emu_repo,
          number: 1,
          emu_owner: @user,
          resolution: "used_in_tests",
          secret_type: "test_slug"
        }
      ).once

      @alerts_service.resolve_alert(repository: @emu_repo, user: @user, numbers: [1], resolution: "used_in_tests", numbers_to_slugs: { 1 => "test_slug" })
    end if TestEnv.test_with_all_emus?

    test "audit entry is logged for resolution" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED)

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil))

      GitHub.expects(:instrument).with(
        "secret_scanning_alert.resolve",
        {
          user: @user,
          repo: @repo,
          number: 1,
          org: @org,
          resolution: "revoked",
          secret_type: "test_slug"
        }
      ).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })
    end

    test "audit entry is logged for reopening" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("reopened").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED).once

      request = resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED)

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(request)).returns(ResponseMock.new(error: nil))

      GitHub.expects(:instrument).with(
        "secret_scanning_alert.reopen",
        {
          user: @user,
          repo: @repo,
          number: 1,
          org: @org,
          secret_type: "test_slug"
        }
      ).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "reopened", numbers_to_slugs: { 1 => "test_slug" })
    end
  end

  context "#report" do
    test "reports alert" do
      data = GitHub::Proto::SecretScanning::Api::V2::ReportTokenResponse.new(
        validity: :TOKEN_VALIDITY_INACTIVE,
        validation_details: { validity_last_checked: Time.now },
        result: :REVOKED
      )
      GitHub::TokenScanning::Service::Client
        .any_instance
        .expects(:report_token)
        .with(equals(report_token_request))
        .returns(ResponseMock.new(error: nil, data: data))
        .once

      response = @alerts_service.report_alert(repository: @repo, user: @user, number: 1)
      refute_nil response
      assert_equal :TOKEN_VALIDITY_INACTIVE, response.validation.validity
      assert_equal :REVOKED, response.result
    end

    test "returns nil when response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:report_token).with(equals(report_token_request)).returns(nil)

      response = @alerts_service.report_alert(repository: @repo, user: @user, number: 1)

      assert_nil response
    end

    test "returns nil when error is present" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:report_token)
        .with(equals(report_token_request))
        .returns(ResponseMock.new(error: ResponseErrorMock.new(msg: "something went wrong"), data: nil)).once

      response = @alerts_service.report_alert(repository: @repo, user: @user, number: 1)

      assert_nil response
    end
  end

  context "#alert_timeline" do
    test "returns timeline data" do
      data = GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse.new(
        total_number_of_events: 0,
        latest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
          events: [],
          cursor: nil
        ),
        earliest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
          events: [],
          cursor: nil
        ),
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(data: data)).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_equal data, response
    end

    test "returns error if response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(nil).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end

    test "returns error if response contains it" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(error: ResponseErrorMock.new(msg: "something went wrong"))).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end

    test "returns error if data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(data: nil)).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end
  end

  context "#on_demand_check" do
    test "returns on demand check" do
      last_checked = Time.now
      data = GitHub::Proto::SecretScanning::Api::V2::GetTokenValidationStatusResponse.new(
          validity: :TOKEN_VALIDITY_ACTIVE,
          validation_details: {
            validity_last_checked: last_checked
          }
      )
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_validation_status).with(equals({
        repository_id: @repo.id,
        token_number: 1,
        requested_by_user_id: @user.id
      })).returns(ResponseMock.new(data: data)).once

      response = @alerts_service.validate_token_on_demand(@repo, @user, 1)

      assert_equal :TOKEN_VALIDITY_ACTIVE, response.validity
      assert_equal last_checked, response.validity_last_checked
      assert_empty response.token_groups
    end
    test "returns error if response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_validation_status).with(equals({
        repository_id: @repo.id,
        token_number: 1,
        requested_by_user_id: @user.id
      })).returns(ResponseMock.new(data: nil)).once

      Failbot.expects(:report).once

      response = @alerts_service.validate_token_on_demand(@repo, @user, 1)

      assert_nil response
    end
  end

  context "#get_workflow_audit" do
    test "returns nil when an error is present" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_workflow_audit).with(
        equals({
            audit_log_actions: [],
            token_type: "GITHUB"
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse)
          ].new(
            error: "error calling openai"
          )
        )

      assert_nil @alerts_service.get_workflow_audit("GITHUB", [], @user)
    end

    test "returns nil when the response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_workflow_audit).with(
        equals({
            audit_log_actions: [],
            token_type: "GITHUB"
          }))
        .returns(nil)

      assert_nil @alerts_service.get_workflow_audit("GITHUB", [], @user)
    end

    test "returns nil when the response data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_workflow_audit).with(
        equals({
          audit_log_actions: [],
          token_type: "GITHUB"
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse)
          ].new(
            data: nil
          )
        )

      assert_nil @alerts_service.get_workflow_audit("GITHUB", [], @user)
    end

    test "sends a request to tss when there were no recent actions" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_workflow_audit).with(
        equals({
          audit_log_actions: [],
          token_type: "GITHUB"
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse.new(audit_response: "test_response")
          )
        )

      assert_equal "test_response", @alerts_service.get_workflow_audit("GITHUB", [], @user)
    end

    test "sends a request to tss when there were recent actions" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_workflow_audit).with(
        equals({
          audit_log_actions: %w(a1 a2),
          token_type: "GITHUB"
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetWorkflowAuditResponse.new(audit_response: "test_response")
          )
        )

      assert_equal "test_response", @alerts_service.get_workflow_audit("GITHUB", %w(a1 a2), @user)
    end
  end

  context "#get_autofix_suggestion" do
    diff1 = <<-DIFF
diff --git a/a.txt b/b.txt
--- a/a.txt
+++ b/a.txt
@@ -1,3 +1,3 @@
  pat:
-- "ghp_t1"
-- "ghp_t2"
+- "${{ secrets.GITHUB_TOKEN_1 }}"
+- "${{ secrets.GITHUB_TOKEN_2 }}"


DIFF
    diff2 = "diff --git a/a.txt b/b.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1,3 +1,3 @@\n pat:\n-- \"ghp_t1\"\n-- \"ghp_t2\"\n+- \"${{ secrets.GITHUB_TOKEN_1 }}\"\n+- \"${{ secrets.GITHUB_TOKEN_2 }}\""
    ending_new_lines_diffs = [diff1, diff2]
    default_explanation = "Consider opening a pull request with a change that removes this token from your codebase."

    test "returns default response when error is present" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_autofix_suggestion).with(
        equals({
            token_number: 200,
            repository_id: @repo.id,
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse)
          ].new(
            error: "error calling openai"
          )
        )

      res = @alerts_service.get_autofix_suggestion(@user, 200, @repo)

      assert_equal default_explanation, res.explanation
      refute res.accept_feedback
      assert_empty res.diff_lines
      assert_equal 1, Failbot.reports.count { |e| e["app"] == SecretScanning::Constants::FAILBOT_APP_NAME }
    end

    test "returns default response when the response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_autofix_suggestion).with(
        equals({
            repository_id: @repo.id,
            token_number: 200,
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse)
          ].new
        )

      res = @alerts_service.get_autofix_suggestion(@user, 200, @repo)

      assert_equal default_explanation, res.explanation
      refute res.accept_feedback
      assert_empty res.diff_lines
      assert_equal 1, Failbot.reports.count { |e| e["app"] == SecretScanning::Constants::FAILBOT_APP_NAME }
    end

    test "returns nil when the response data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_autofix_suggestion).with(
        equals({
            repository_id: @repo.id,
            token_number: 200,
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse)
          ].new(data: nil)
        )


      res = @alerts_service.get_autofix_suggestion(@user, 200, @repo)

      assert_equal default_explanation, res.explanation
      refute res.accept_feedback
      assert_empty res.diff_lines
      assert_equal 1, Failbot.reports.count { |e| e["app"] == SecretScanning::Constants::FAILBOT_APP_NAME }
    end

    test "parses diff and returns lines from tss" do
      ending_new_lines_diffs.each do |diff|
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_autofix_suggestion).with(
          equals({
              repository_id: @repo.id,
              token_number: 200,
            }))
          .returns(
            Twirp::ClientResp[
              T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse)
            ].new(data: GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse.new(diff: "encrypted_diff", explanation: "an explanation"))
          )
        SecretScanning::Encryption::EncryptedSecretsCryptoHelper.expects(:decrypt_encrypted_secret).returns(diff)

        res = @alerts_service.get_autofix_suggestion(@user, 200, @repo)

        assert_equal "an explanation", res.explanation
        assert res.accept_feedback
        assert_equal 6, res.diff_lines.length
        assert_equal 0, Failbot.reports.count { |e| e["app"] == SecretScanning::Constants::FAILBOT_APP_NAME }
        assert_equal [:HUNK, :CONTEXT, :DELETION, :DELETION, :ADDITION, :ADDITION], res.diff_lines.map { |dl| dl[:type] }
      end
      assert_dogstats_increment(2, "secret_scanning.alerts_service.get_autofix_suggestion.parsed", tags: ["success:true"])
    end

    test "returns default response if parsing fails" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_autofix_suggestion).with(
        equals({
            repository_id: @repo.id,
            token_number: 200,
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse)
          ].new(data: GitHub::Proto::SecretScanning::Api::V2::GetAutofixSuggestionResponse.new(diff: "encrypted_diff", explanation: "an explanation"))
        )
      SecretScanning::Encryption::EncryptedSecretsCryptoHelper.expects(:decrypt_encrypted_secret).returns("a diff")

      res = @alerts_service.get_autofix_suggestion(@user, 200, @repo)

      assert_equal default_explanation, res.explanation
      refute res.accept_feedback
      assert_equal 0, res.diff_lines.length
      assert_equal 1, Failbot.reports.count { |e| e["app"] == SecretScanning::Constants::FAILBOT_APP_NAME }
      assert_dogstats_increment(1, "secret_scanning.alerts_service.get_autofix_suggestion.parsed", tags: ["success:false"])
    end
  end

  context "#get_adversarial_audit" do
    test "returns nil when an error is present" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            error: "error calling openai"
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_nil @alerts_service.get_adversarial_audit(fgp_permissions, @user)
    end

    test "returns nil when the response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            }
          }))
        .returns(nil)
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_nil @alerts_service.get_adversarial_audit(fgp_permissions, @user)
    end

    test "returns nil when the response data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: nil
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_nil @alerts_service.get_adversarial_audit(fgp_permissions, @user)
    end

    test "makes a request to TSS for an FGP with no permissions" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse.new(audit_response: "test_response")
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      res = @alerts_service.get_adversarial_audit(fgp_permissions, @user)
      assert_equal "test_response", res
    end

    test "makes a request to TSS for an FGP with permissions" do
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({ "metadata" => :write, "repo" => :read, "actions" => :write })
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: [
                { scope: "metadata", permission: "write" },
                { scope: "repo", permission: "read" },
                { scope: "actions", permission: "write" },
              ]
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse.new(audit_response: "test_response")
          )
        )

      res = @alerts_service.get_adversarial_audit(fgp_permissions, @user)
      assert_equal "test_response", res
    end

    test "makes a request to tss for a patv1 with more than 0 scopes" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v1_permissions: {
              scopes: %w(s1 s2)
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse.new(audit_response: "test_response")
          )
        )
      classic_pat_permissions = SecretScanning::Models::Permissions::Classic.new(all_scopes: %w(s1 s2), scopes_with_parents: {})

      res = @alerts_service.get_adversarial_audit(classic_pat_permissions, @user)
      assert_equal "test_response", res
    end

    test "makes a request to tss for a patv1 no scopes" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_adversarial_audit).with(
        equals({
            pat_v1_permissions: {
              scopes: []
            }
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse.new(audit_response: "test_response")
          )
        )
      classic_pat_permissions = SecretScanning::Models::Permissions::Classic.new(all_scopes: [], scopes_with_parents: {})

      res = @alerts_service.get_adversarial_audit(classic_pat_permissions, @user)
      assert_equal "test_response", res
    end
  end

  context "#get_permission_audit" do
    test "returns nil when an error is present" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            },
            audit_log_actions: [],
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            error: "error calling openai"
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_equal [nil, nil], @alerts_service.get_permission_audit([], fgp_permissions, @user)
    end

    test "returns nil when the response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            },
            audit_log_actions: []
          }))
        .returns(nil)
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_equal [nil, nil], @alerts_service.get_permission_audit([], fgp_permissions, @user)
    end

    test "returns nil when the response data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            },
            audit_log_actions: []
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetAdversarialAuditResponse)
          ].new(
            data: nil
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      assert_equal [nil, nil], @alerts_service.get_permission_audit([], fgp_permissions, @user)
    end

    test "makes and maps  a request to TSS for an FGP with no permissions and no audit log data" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: []
            },
            audit_log_actions: []
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
              summary: "test_response",
              removed_pat_v2_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions.new(permissions: []))
          )
        )
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({})

      summary, permissions = @alerts_service.get_permission_audit([], fgp_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {},
        "group_label" => "Permission",
        "value_label" => "Target"
      }, permissions.serialize)
    end

    test "makes and maps a request to TSS for an FGP with permissions and audit log data" do
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({ "metadata" => :write, "repo" => :read, "actions" => :write })
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: [
                { scope: "metadata", permission: "write" },
                { scope: "repo", permission: "read" },
                { scope: "actions", permission: "write" },
              ]
            },
            audit_log_actions: %w(a1 a2),
          }))
          .returns(
            Twirp::ClientResp[
              T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
            ].new(
              data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
                summary: "test_response",
                removed_pat_v2_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions.new(permissions: [
                  GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions::Permission.new(scope: "metadata", permission: "write")
                ])
              )
            )
          )

      summary, permissions = @alerts_service.get_permission_audit(%w(a1 a2), fgp_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {
          "Read and Write" => [
            { "value" => "metadata", "group" => "Read and Write", "deleted" => true },
            { "value" => "actions", "group" => "Read and Write", "deleted" => false }
          ],
          "Read" => [
            { "value" => "repo", "group" => "Read", "deleted" => false }
          ]
        },
        "group_label" => "Permission",
        "value_label" => "Target"
      }, permissions.serialize)
    end

    test "makes and maps a request to TSS for an FGP with permissions and mismatched response" do
      fgp_permissions = SecretScanning::Models::Permissions::Fgp.new_from_permissions({ "metadata" => :write, "repo" => :read, "actions" => :write })
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v2_permissions: {
              permissions: [
                { scope: "metadata", permission: "write" },
                { scope: "repo", permission: "read" },
                { scope: "actions", permission: "write" },
              ]
            },
            audit_log_actions: %w(a1 a2),
          }))
          .returns(
            Twirp::ClientResp[
              T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
            ].new(
              data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
                summary: "test_response",
                removed_pat_v2_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions.new(permissions: [
                  GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions::Permission.new(scope: "test", permission: "read")
                ])
              )
            )
          )

      summary, permissions = @alerts_service.get_permission_audit(%w(a1 a2), fgp_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {
          "Read and Write" => [
            { "value" => "metadata", "group" => "Read and Write", "deleted" => false },
            { "value" => "actions", "group" => "Read and Write", "deleted" => false }
          ],
          "Read" => [
            { "value" => "repo", "group" => "Read", "deleted" => false }
          ]
        },
        "group_label" => "Permission",
        "value_label" => "Target"
      }, permissions.serialize)
    end


    test "makes and maps  a request to tss for a patv1 with more than 0 scopes and audit log entries" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v1_permissions: {
              scopes: %w(s1 s2)
            },
            audit_log_actions: %w(a1 a2)
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
              summary: "test_response",
              removed_pat_v1_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV1Permissions.new(scopes: ["s1"]))
            )
          )
      classic_pat_permissions = SecretScanning::Models::Permissions::Classic.new(all_scopes: %w(s1 s2), scopes_with_parents: { "parent" => %w(s1 s2) })

      summary, permissions = @alerts_service.get_permission_audit(%w(a1 a2), classic_pat_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {
          "parent" => [
            { "value" => "s1", "group" => "parent", "deleted" => true },
            { "value" => "s2", "group" => "parent", "deleted" => false }
          ]
        },
        "group_label" => "Target",
        "value_label" => "Permission"
      }, permissions.serialize)
    end

    test "makes and maps  a request to tss for a patv1 with more than 0 scopes and mismatched response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v1_permissions: {
              scopes: %w(s1 s2)
            },
            audit_log_actions: %w(a1 a2)
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
              summary: "test_response",
              removed_pat_v1_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV1Permissions.new(scopes: ["s3"]))
            )
          )
      classic_pat_permissions = SecretScanning::Models::Permissions::Classic.new(all_scopes: %w(s1 s2), scopes_with_parents: { "parent" => %w(s1 s2) })

      summary, permissions = @alerts_service.get_permission_audit(%w(a1 a2), classic_pat_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {
          "parent" => [
            { "value" => "s1", "group" => "parent", "deleted" => false },
            { "value" => "s2", "group" => "parent", "deleted" => false }
          ]
        },
        "group_label" => "Target",
        "value_label" => "Permission"
      }, permissions.serialize)
    end

    test "makes and maps  a request to tss for a patv1 no scopes" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_permission_audit).with(
        equals({
            pat_v1_permissions: {
              scopes: []
            },
            audit_log_actions: []
          }))
        .returns(
          Twirp::ClientResp[
            T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse)
          ].new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetPermissionAuditResponse.new(
              summary: "test_response",
              removed_pat_v1_permissions: GitHub::Proto::SecretScanning::Api::V2::PATV1Permissions.new(scopes: []))
            )
          )
      classic_pat_permissions = SecretScanning::Models::Permissions::Classic.new(all_scopes: [], scopes_with_parents: {})

      summary, permissions = @alerts_service.get_permission_audit([], classic_pat_permissions, @user)
      assert_equal("test_response", summary)
      assert_equal({
        "groups" => {},
        "group_label" => "Target",
        "value_label" => "Permission"
      }, permissions.serialize)
    end
  end

  context "#update_token_with_closure_request_id" do
    test "returns nil when the response succeeds" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_token_with_closure_exemption_request_id).with(
        equals({
            repository_id: @repo.id,
            token_number: 1,
            closure_exemption_request_id: 2,
          }))
        .returns(ResponseMock.new(data: nil, error: nil))
      response = @alerts_service.update_token_with_closure_request_id(@repo, @user, 1, 2)
      assert_nil response
    end

    test "returns a ServiceError if TSS returns an error" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_token_with_closure_exemption_request_id).with(
        equals({
            repository_id: @repo.id,
            token_number: 1,
            closure_exemption_request_id: 2,
          }))
        .returns(ResponseMock.new(data: nil, error: ResponseErrorMock.new(msg: "something went wrong")))
      response = @alerts_service.update_token_with_closure_request_id(@repo, @user, 1, 2)
      refute_nil response
      assert_equal "something went wrong", response.to_s
    end


  end

  def get_token_request
    {
      repository_id: @repo.id,
      token_id: 1,
      include_commit_oids: true,
      include_included_locations: true,
      limit: SecretScanning::Services::AlertsService::LOCATIONS_PER_PAGE,
      page: 1,
      feature_flags: ["stop_using_has_valid_locations"],
      include_location_count: true,
      include_config_filters: true,
      include_related_alerts: false
    }
  end

  def resolve_token_request(resolution, dismissal_comment = nil)
    {
      repository_id: @repo.id,
      token_numbers: [1],
      resolver_id: @user.id,
      resolution: resolution,
      default_branch_name: @repo.default_branch,
      feature_flags: [],
      resolution_comment: dismissal_comment
    }
  end

  def report_token_request
    {
      repository_id: @repo.id,
      number: 1,
      reporting_user_id: @user.id
    }
  end

  def get_token_for_timeline
    token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2023-03-10"),
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
      id: 1,
      label: "GitHub Personal Access Token",
      token_type: "GITHUB",
      repository_id: @repo.id,
      number: 1,
    )

    GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
  end
end
