# typed: true
# frozen_string_literal: true
require "test_helper"
module ::SecretScanning::Features
  class SecretScanningAdvancedSecurityHelperTest < GitHub::TestCase
    fixtures do
      @owner = create(:user)
      if GitHub.enterprise?
        @business = create(:global_business)
        @user = create(:user)
        @user_owned_repo = create(:private_repository, force_user_owned: true, owner: @user)
      else
        @business = create(:business, :enterprise_managed)
        @emu_user = create(:emu, business: @business)
        @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
      end
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
    end

    setup do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
    end

    context "#advanced_security_available?" do
      test "returns true for EMU when feature flag enabled", skip_enterprise: true do
        assert SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@emu_owned_repo)
      end

      test "returns false for EMU when feature flag disabled", enterprise_only: true do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
        refute SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@user_owned_repo)
      end
    end

    context "#advanced_security_configurable?" do
      test "returns true for EMU when feature flag enabled", skip_enterprise: true do
        assert SecretScanning::Features::AdvancedSecurityHelper.advanced_security_configurable?(@emu_owned_repo)
      end

      test "returns false for EMU when feature flag disabled", enterprise_only: true do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
        refute SecretScanning::Features::AdvancedSecurityHelper.advanced_security_configurable?(@user_owned_repo)
      end
    end
  end
end
