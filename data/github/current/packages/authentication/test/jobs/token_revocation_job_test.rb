# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/dogstats_test_helpers"

class TokenRevocationJobTest < GitHub::TestCase
  include JobTestHelper
  include AuditLog::IntegrationTestHelpers
  include ActionMailer::TestHelper

  setup do
    enable_feature_flag(:credential_revocation_api)
    enable_feature_flag(:credential_revocation_api_mailers)
  end

  fixtures do
    @user = create(:user)

    @pat1 = make_personal_access_token(@user, "repo")
    @token1 = @pat1.set_random_token_pair
    @pat1.save

    @pat2 = make_personal_access_token(@user, "repo")
    @token2 = @pat2.set_random_token_pair
    @pat2.save

    @tokens = {
      PERSONAL_ACCESS_TOKEN: [@token1, @token2],
      FINE_GRAINED_PERSONAL_ACCESS_TOKEN: [],
      UNKNOWN: [],
    }
  end

  test "token revocation job enqueued" do
    assert_no_enqueued_jobs
    assert_performed_audit_entries(count: 0, only: "oauth_access.revoke") do
      assert_enqueued_with(job: TokenRevocationJob, args: [@tokens], queue: "token_revocation") do
        TokenRevocationJob.perform_later(@tokens)
      end
    end

    assert_enqueued_jobs(1, only: TokenRevocationJob, queue: "token_revocation")
  end

  test "token revocation job performs" do
    assert_no_performed_jobs

    events = assert_performed_audit_entries(count: 2, only: "oauth_access.revoke") do
      perform_enqueued_jobs(only: TokenRevocationJob) do
        TokenRevocationJob.perform_later(@tokens)
      end
    end

    @pat1.reload
    @pat2.reload

    assert @pat1.expired?
    assert @pat2.expired?


    assert_performed_jobs(1, only: TokenRevocationJob, queue: "token_revocation")
    assert_equal last_performed_audit_entries, events

    expected_payload = {
      action: "oauth_access.revoke",
      actor: "ghost",
      reason: "revoked by the GitHub API token revocation endpoint",
      operation_type: "modify",
    }

    first_payload = expected_payload.merge({ hashed_token: @pat1.hashed_token })
    assert_subset_hash(first_payload, events.first)

    second_payload = expected_payload.merge({ hashed_token: @pat2.hashed_token })
    assert_subset_hash(second_payload, events.second)
  end

  test "sends email to user when token is revoked" do
    # add a fake PAT to the list of tokens to be revoked
    @tokens[:PERSONAL_ACCESS_TOKEN] << "ghp_#{SecureRandom.alphanumeric(36)}"

    RevokedCredentialMailer
      .expects(:personal_access_token_revoked)
      .once
      .with(@user, @pat1.description, type: TokenRevocation::Helper::PAT_CREDENTIAL)
      .returns(stub(deliver_later: nil))

    RevokedCredentialMailer
      .expects(:personal_access_token_revoked)
      .once
      .with(@user, @pat2.description, type: TokenRevocation::Helper::PAT_CREDENTIAL)
      .returns(stub(deliver_later: nil))

    TokenRevocationJob.perform_now(@tokens)
  end

  test "doesn't enqueue the job if the feature flag is disabled" do
    disable_feature_flag(:credential_revocation_api)
    assert_no_enqueued_jobs
    assert_performed_audit_entries(count: 0) do
      TokenRevocationJob.perform_later(@tokens)
    end
    assert_enqueued_jobs(0, only: TokenRevocationJob, queue: "token_revocation")
  end

  test "doesn't perform the job if the feature flag is disabled" do
    disable_feature_flag(:credential_revocation_api)
    assert_no_performed_jobs
    assert_performed_audit_entries(count: 0) do
      perform_enqueued_jobs(only: TokenRevocationJob) do
        TokenRevocationJob.perform_later(@tokens)
      end
    end
    assert_performed_jobs(0, only: TokenRevocationJob, queue: "token_revocation")
  end

  context "review-lab" do
    test "doesn't enqueue the job if the review-lab feature flag is disabled in review lab" do
      disable_feature_flag(:credential_revocation_api)
      disable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(true)
      assert_no_enqueued_jobs
      TokenRevocationJob.perform_later(@tokens)
      assert_enqueued_jobs(0, only: TokenRevocationJob, queue: "token_revocation")
    end

    test "doesn't perform the job if the review-lab feature flag is disabled in review lab" do
      disable_feature_flag(:credential_revocation_api)
      disable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(true)
      assert_no_performed_jobs
      perform_enqueued_jobs(only: TokenRevocationJob) do
        TokenRevocationJob.perform_later(@tokens)
      end
      assert_performed_jobs(0, only: TokenRevocationJob, queue: "token_revocation")
    end

    test "enqueues the job if the review-lab feature flag is enabled in review lab" do
      disable_feature_flag(:credential_revocation_api)
      enable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(true)
      assert_no_enqueued_jobs
      assert_enqueued_with(job: TokenRevocationJob, args: [@tokens], queue: "token_revocation") do
        TokenRevocationJob.perform_later(@tokens)
      end
      assert_enqueued_jobs(1, only: TokenRevocationJob, queue: "token_revocation")
    end

    test "performs the job if the review-lab feature flag is enabled in review lab" do
      disable_feature_flag(:credential_revocation_api)
      enable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(true)
      assert_no_performed_jobs
      perform_enqueued_jobs(only: TokenRevocationJob) do
        TokenRevocationJob.perform_later(@tokens)
      end
      assert_performed_jobs(1, only: TokenRevocationJob, queue: "token_revocation")
    end
  end
end
