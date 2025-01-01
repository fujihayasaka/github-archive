# typed: true
# frozen_string_literal: true

require "test_helper"

class InteractionLimitTest < GitHub::TestCase
  fixtures do
    @repo, repo2 = create_list(:repository, 2, :org_owned)
    @local_limit = @repo.enable_repo_interaction_limit(restriction: :sockpuppet_disallowed, expires_at: 1.week.from_now)
    @overall_limit = repo2.owner.enable_repo_interaction_limit(restriction: :collaborators_only, expires_at: 1.week.ago)
  end

  context "validations" do
    test "requires a user" do
      limit = InteractionLimit.new(repository: @repo, expires_at: 1.week.from_now)
      refute_predicate limit, :valid?
      refute_empty limit.errors[:user_id]
    end

    test "requires an expiration datetime" do
      limit = InteractionLimit.new(repository: @repo, user: @repo.owner)
      refute_predicate limit, :valid?
      refute_empty limit.errors[:expires_at]
    end

    test "repository limits require a restriction" do
      limit = InteractionLimit.new(target: :repository, repository: @repo, user: @repo.owner, expires_at: 1.week.from_now)
      refute_predicate limit, :valid?
      refute_empty limit.errors[:restriction]
    end

    test "user limits do not require a restriction" do
      limit = InteractionLimit.new(target: :user, user: @repo.owner, expires_at: 1.week.from_now)
      assert_predicate limit, :valid?
    end
  end

  context "scopes" do
    test "finds expired limits" do
      expired_limits = InteractionLimit.expired
      assert_includes expired_limits, @overall_limit
      refute_includes expired_limits, @local_limit
    end

    test "finds unexpired limits" do
      unexpired_limits = InteractionLimit.not_expired
      refute_includes unexpired_limits, @overall_limit
      assert_includes unexpired_limits, @local_limit
    end
  end


  context "repo limits" do
    test "identifies local limits" do
      assert_predicate @local_limit, :local?
      refute_predicate @overall_limit, :local?
    end

    test "identifies overall limits" do
      assert_predicate @overall_limit, :overall?
      refute_predicate @local_limit, :overall?
    end

    test "identifies the limit origin" do
      user_owned_repo = create(:repository, force_user_owned: true)
      user_limit = user_owned_repo.owner.enable_repo_interaction_limit(restriction: :contributors_only, expires_at: 1.week.from_now)

      assert_equal :repository, @local_limit.origin
      assert_equal :organization, @overall_limit.origin
      assert_equal :user, user_limit.origin
    end
  end
end
