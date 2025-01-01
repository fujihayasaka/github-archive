# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::PlaygroundAccessResultTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    unless GitHub.enterprise?
      @emu_business = create(:business, :enterprise_managed)
      @emu_owner = @emu_business.owners.first
      @emu_org = create(:organization, business: @emu_business, admin: @emu_owner)
      @emu = create :emu, business: @emu_business
    end
  end

  setup do
    disable_feature_flag(:project_neutron_emergency_restrict_access)
  end

  context ".for" do
    test "returns false when not logged in" do
      result = GitHubModels::PlaygroundAccessResult.for(nil)
      refute_predicate result, :accessible?
    end

    test "when the emergency flag is on, returns false for new users" do
      enable_feature_flag(:project_neutron_emergency_restrict_access)
      result = GitHubModels::PlaygroundAccessResult.for(@user)
      refute_predicate result, :accessible?
    end

    test "when the emergency flag is on, returns true for older users" do
      enable_feature_flag(:project_neutron_emergency_restrict_access)
      @user.update!(created_at: 1.year.ago)

      result = GitHubModels::PlaygroundAccessResult.for(@user)

      assert_predicate result, :accessible?
    end

    test "returns false when user is spammy", spammy_only: true do
      spammy_user = create(:spammy_user)
      result = GitHubModels::PlaygroundAccessResult.for(spammy_user)
      refute_predicate result, :accessible?
    end

    test "returns false when user is suspended" do
      suspended_user = create(:suspended_user)
      result = GitHubModels::PlaygroundAccessResult.for(suspended_user)
      refute_predicate result, :accessible?
    end

    test "returns false when user has trade restrictions" do
      @user.trade_controls_restriction.full!
      result = GitHubModels::PlaygroundAccessResult.for(@user)
      refute_predicate result, :accessible?
    end

    test "returns false when user is Copilot blocked" do
      Copilot::User.new(@user).administrative_block!(create(:user), "reason")
      result = GitHubModels::PlaygroundAccessResult.for(@user)
      refute_predicate result, :accessible?
    end

    test "returns false when user is an emu that doesn't have models enabled", skip_enterprise: true do
      result = GitHubModels::PlaygroundAccessResult.for(@emu)
      refute_predicate result, :accessible?
    end

    test "returns false when user is an emu_org whose business doesn't have models enabled", skip_enterprise: true do
      result = GitHubModels::PlaygroundAccessResult.for(@emu_org)
      refute_predicate result, :accessible?
    end

    test "returns true when logged in, not spammy, not suspended" do
      result = GitHubModels::PlaygroundAccessResult.for(@user)
      assert_predicate result, :accessible?
    end

    test "returns true when user is a logged in emu with access", skip_enterprise: true do
      @emu.enterprise_managed_business.enable_models_access(@emu_owner)

      result = GitHubModels::PlaygroundAccessResult.for(@emu)
      assert_predicate result, :accessible?
    end

    test "can handle an org as a user" do
      org = create(:organization)
      result = GitHubModels::PlaygroundAccessResult.for(org)
      assert_predicate result, :accessible?
    end

    test "can handle an emu_org as a user", skip_enterprise: true do
      @emu_org.business.enable_models_access(@emu_owner)
      result = GitHubModels::PlaygroundAccessResult.for(@emu_org)
      assert_predicate result, :accessible?
    end
  end
end
