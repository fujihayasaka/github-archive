# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GhesBackfillDefaultFgPatLimitPolicyJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    GitHub::Enterprise.ensure_business!

    @business = GitHub.global_business
    @business.disable_fine_grained_personal_access_token_expiration_limit(actor: User.ghost)
  end

  test "sets the default FG PAT limit policy when it is not set" do
    refute Apps::KV.store.exists(GhesBackfillDefaultFgPatLimitPolicyJob::BACKFILL_COMPLETED_KEY).value { false }

    assert_changes -> { @business.reload.fine_grained_personal_access_token_expiration_limit  }, from: nil, to: Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT do
      GhesBackfillDefaultFgPatLimitPolicyJob.perform_now
    end

    assert Apps::KV.store.exists(GhesBackfillDefaultFgPatLimitPolicyJob::BACKFILL_COMPLETED_KEY).value { false }
  end

  test "does not set the default FG PAT limit policy when it is already set" do
    refute Apps::KV.store.exists(GhesBackfillDefaultFgPatLimitPolicyJob::BACKFILL_COMPLETED_KEY).value { false }
    @business.set_fine_grained_personal_access_token_expiration_limit(actor: User.ghost, expiration: 100)

    assert_no_changes -> { @business.reload.fine_grained_personal_access_token_expiration_limit  } do
      GhesBackfillDefaultFgPatLimitPolicyJob.perform_now
    end

    assert Apps::KV.store.exists(GhesBackfillDefaultFgPatLimitPolicyJob::BACKFILL_COMPLETED_KEY).value { false }
  end

  test "does not change the FG PAT limit policy when the job already ran" do
    refute Apps::KV.store.exists(GhesBackfillDefaultFgPatLimitPolicyJob::BACKFILL_COMPLETED_KEY).value { false }
    GhesBackfillDefaultFgPatLimitPolicyJob.perform_now
    @business.disable_fine_grained_personal_access_token_expiration_limit(actor: User.ghost) # disable the limit after the backfill

    assert_no_changes -> { @business.reload.fine_grained_personal_access_token_expiration_limit } do
      GhesBackfillDefaultFgPatLimitPolicyJob.perform_now
    end
  end
end if GitHub.enterprise?
