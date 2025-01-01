# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CleanExpiredInteractionLimitsJobTest < GitHub::TestCase
  include ActiveJob::TestHelper
  include JobTestHelper

  test "deletes expired interaction limits" do
    repo = create(:repository)
    owner = repo.owner
    expired_limit = repo.create_repo_interaction_limit(restriction: :collaborators_only, expires_at: 1.day.ago, user: owner)
    unexpired_limit = owner.create_repo_interaction_limit(restriction: :contributors_only, expires_at: 1.day.from_now)

    CleanExpiredInteractionLimitsJob.perform_now

    refute InteractionLimit.exists?(expired_limit.id), "expired limit should be deleted"
    assert InteractionLimit.exists?(unexpired_limit.id), "unexpired limit should not be deleted"
  end
end
