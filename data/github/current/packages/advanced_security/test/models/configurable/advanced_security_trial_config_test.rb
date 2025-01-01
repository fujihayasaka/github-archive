# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurityTrialConfigTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org_without_config = create(:organization)
  end

  context "#advanced_security_trial_enabled_for_entity? for business" do
    test "returns false if new_record?" do
      org = build(:organization)
      assert org.new_record?
      refute org.advanced_security_trial_enabled_for_entity?
    end

    test "returns false if no ADVANCED_SECURITY_TRIAL_KEY config entry" do
      @org.disable_advanced_security_trial_for_entity(actor: @user)
      refute @org.advanced_security_trial_enabled_for_entity?
    end

    test "returns true if ADVANCED_SECURITY_TRIAL_KEY config entry" do
      @org.enable_advanced_security_trial_for_entity(actor: @user)
      assert @org.advanced_security_trial_enabled_for_entity?
    end
  end

  context "#get_advanced_security_trial_expires_at" do
    test "returns config_date when present" do
      freeze_time do
        @org.set_advanced_security_trial_expires_at(actor: @user, date: Date.today)
        expires_at = @org.get_advanced_security_trial_expires_at

        assert_equal Date.today, expires_at
      end
    end
  end
end
