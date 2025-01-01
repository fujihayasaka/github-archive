# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAdvancedSecurityFeaturesTest < GitHub::TestCase
  fixtures do
    return if GitHub.enterprise?
    @owner = create(:user)
    @business = create(:business, :enterprise_managed)
    @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    # EMU
    @emu_user = create(:emu, business: @business)
    @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
  end

  context "feature_visible?", skip_enterprise: true do
    test "returns true for EMU" do
      ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(@emu_user)
      assert ghas_for_users.feature_available?
    end

    test "returns false for non-EMU" do
      ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(@owner)
      refute ghas_for_users.feature_available?
    end
  end

  if GitHub.enterprise?
    class UserAdvancedSecurityFeaturesEnterpriseTest < GitHub::TestCase
      fixtures do
        @business = GitHub.global_business || create(:business, seats: 5)
        @owner = @business.admins.first
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        @rando = create(:user)
      end

      context "feature_visible?" do
        test "returns true when enabled at instance level" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?

          ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(@rando)
          assert ghas_for_users.feature_available?
        end

        test "returns false when enabled at instance level" do
          GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false) if GitHub.enterprise?

          ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(@rando)
          refute ghas_for_users.feature_available?
        end
      end
    end
  end
end
