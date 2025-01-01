# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryInvitationRateLimitOverrideTest < GitHub::TestCase

  fixtures do
    @repo = create(:repository)
  end

  test "overrides the rate limit for a repo" do
    RepositoryInvitationRateLimitOverride.override!(@repo.id)
    assert RepositoryInvitationRateLimitOverride.overridden?(@repo.id)
  end

  test "correctly reports no override on a repo" do
    refute RepositoryInvitationRateLimitOverride.overridden?(@repo.id)
  end

end
