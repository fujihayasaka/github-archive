# typed: true
# frozen_string_literal: true

require "test_helper"

class IntelIpRestrictionFlagTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @flagged_owner = create(:organization)
    @flagged_private_root = create(:private_repository, :minimal, owner: @flagged_owner)
    @flagged_private_fork = fast_fork_repo(@flagged_private_root)
    @flagged_public_root = create(:repository, :minimal, owner: @flagged_owner)
    @flagged_public_fork = fast_fork_repo(@flagged_public_root)

    @unflagged_owner = create(:organization)
    @unflagged_private_root = create(:private_repository, :minimal, owner: @unflagged_owner)
    @unflagged_private_fork = fast_fork_repo(@unflagged_private_root)
  end

  setup do
    enable_feature_flag(:intel_fork_ip_allowlist_org, @flagged_owner)
    disable_feature_flag(:intel_fork_ip_allowlist_org, @unflagged_owner)
  end

  context "#ip_restricted_private_fork?", skip_enterprise: true do
    test "returns true for private forks with feature flag enabled, false otherwise" do
      assert_predicate @flagged_private_fork, :ip_restricted_private_fork?
      refute_predicate @flagged_private_root, :ip_restricted_private_fork?
      refute_predicate @unflagged_private_root, :ip_restricted_private_fork?
      refute_predicate @unflagged_private_fork, :ip_restricted_private_fork?
      refute_predicate @flagged_public_root, :ip_restricted_private_fork?
      refute_predicate @flagged_public_fork, :ip_restricted_private_fork?
    end
  end
end
