# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/missing_record_helper"

class Copilot::OrganizationCleanerHelpersTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include MissingRecordHelper

  fixtures do
    @invalid_states = [
      {
        state: :deleted?,
        standalone: :clean,
        enterprise_owned: :revoke_to_enterprise
      }, {
        state: :disabled?,
        standalone: :revoke_to_org,
        enterprise_owned: :revoke_to_org
      }, {
        state: :archived?,
        standalone: :clean,
        enterprise_owned: :revoke_to_enterprise
      }, {
        state: :spammy?,
        standalone: :revoke_to_org,
        enterprise_owned: :revoke_to_org
      }, {
        state: :soft_deleted?,
        standalone: :revoke_to_org,
        enterprise_owned: :revoke_to_org
      }
    ]
  end

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

  def get_standalone_orgs
    standalone_org = create(:organization, :zuora)
    standalone_org_with_revokable_access = create(:organization, :zuora)
    org_trial = create(:copilot_business_trial, :organization)
    org_with_trial = org_trial.trialable

    [
      { org: standalone_org, revokable: false, trial: false },
      { org: org_with_trial, revokable: false, trial: true },
      { org: standalone_org_with_revokable_access, revokable: true, trial: false },
    ]
  end

  def get_enterprise_owned_orgs
    business = create(:business)
    enterprise_owned_org = create(:organization, :enterprise_linked, business: business)
    enterprise_owned_org_with_revokable_access = create(:organization, :enterprise_linked, business: business)
    org_trial = create(:copilot_business_trial, :organization, trialable: create(:organization, :enterprise_linked, business: business))
    org_with_trial = org_trial.trialable

    [
      { org: enterprise_owned_org, revokable: false, trial: false },
      { org: org_with_trial, revokable: false, trial: true },
      { org: enterprise_owned_org_with_revokable_access, revokable: true, trial: false },
    ]
  end

  context "check_cleaner" do
    context "standalone orgs", skip_in_multitenant_mode: true, skip_with_all_emus: true do
      test "valid org" do
        org = create(:organization, :zuora)
        Copilot::Organization.new(org).enable_copilot!

        result = Copilot::OrganizationCleanupDecider.new(org).get_action
        assert_equal :none, result
      end

      test "trial and no other issues" do
        org_trial = create(:copilot_business_trial, :organization)
        org = org_trial.trialable
        result = Copilot::OrganizationCleanupDecider.new(org).get_action
        assert_equal :none, result
      end

      test "trade restrictions" do
        restrictions = [:has_full_trade_restrictions, :has_any_trade_restrictions]

        get_standalone_orgs.each do |test_case|
          restrictions.each do |restriction|
            Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({
              billable: false,
              reason: restriction
            })

            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action
            assert_equal :clean, result
          end
        end
      end

      test "invalid states" do
        get_standalone_orgs.each do |test_case|
          @invalid_states.each do |state|
            enable_feature_flag(:copilot_revokable_access, test_case[:org]) if test_case[:revokable]
            test_case[:org].stubs(state[:state]).returns(true)

            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action

            if test_case[:revokable]
              assert_equal state[:standalone], result
            else
              assert_equal :clean, result
            end

            test_case[:org].unstub(state[:state])
          end
        end
      end

      context "suspension" do
        test "any zuora-billed org" do
          get_standalone_orgs.each do |test_case|
            enable_feature_flag(:copilot_revokable_access, test_case[:org]) if test_case[:revokable]
            test_case[:org].stubs(:suspended?).returns(true)

            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action
            assert_equal :clean, result
          end
        end

        test "azure-billed org" do
          org = create(:organization, :with_azure_subscription)
          org.customer.update(metered_via_azure: true)
          org.stubs(:suspended?).returns(true)

          result = Copilot::OrganizationCleanupDecider.new(org).get_action
          # without revokable accesss
          assert_equal :clean, result

          enable_feature_flag(:copilot_revokable_access, org)
          result = Copilot::OrganizationCleanupDecider.new(org).get_action
          assert_equal :revoke_to_org, result
        end
      end

      test "copilot disabled" do
        get_standalone_orgs.each do |test_case|
          # Trials dont care if copilot is disabled, it might have been an error
          next if test_case[:trial]

          enable_feature_flag(:copilot_revokable_access, test_case[:org]) if test_case[:revokable]

          result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action

          if test_case[:revokable]
            assert_equal :revoke_to_org, result
          else
            assert_equal :clean, result
          end
        end
      end
    end

    context "enterprise owned orgs" do
      test "valid org" do
        get_enterprise_owned_orgs.each do |test_case|
          Copilot::Business.new(test_case[:org].business).enable_copilot_for_all_organizations!

          result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action
          assert_equal :none, result
        end
      end

      test "trial and no other issues" do
        org = create(:organization, :enterprise_linked)
        create(:copilot_business_trial, :organization, trialable: org)

        result = Copilot::OrganizationCleanupDecider.new(org).get_action
        assert_equal :none, result
      end

      test "trade restrictions" do
        restrictions = [:has_full_trade_restrictions, :has_any_trade_restrictions]

        get_enterprise_owned_orgs.each do |test_case|
          restrictions.each do |restriction|
            Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({
              billable: false,
              reason: restriction
            })

            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action
            assert_equal :clean, result
          end
        end
      end

      test "invalid states" do
        get_enterprise_owned_orgs.each do |test_case|
          @invalid_states.each do |state|
            enable_feature_flag(:copilot_revokable_access, test_case[:org].business) if test_case[:revokable]
            test_case[:org].stubs(state[:state]).returns(true)

            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action

            if test_case[:revokable]
              assert_equal state[:enterprise_owned], result
            else
              assert_equal :clean, result
            end

            test_case[:org].unstub(state[:state])
          end
        end
      end

      context "suspension" do
        test "any zuora-billed org" do
          get_enterprise_owned_orgs.each do |test_case|
            enable_feature_flag(:copilot_revokable_access, test_case[:org].business) if test_case[:revokable]
            test_case[:org].stubs(:suspended?).returns(true)
            result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action
            assert_equal :clean, result
          end
        end

        test "azure-billed org" do
          biz = create(:business, :with_azure_subscription)
          biz.customer.update(metered_via_azure: true)
          org = create(:organization, :enterprise_linked, business: biz)
          org.stubs(:suspended?).returns(true)

          result = Copilot::OrganizationCleanupDecider.new(org).get_action
          # without revokable accesss
          assert_equal :clean, result

          enable_feature_flag(:copilot_revokable_access, biz)
          result = Copilot::OrganizationCleanupDecider.new(org).get_action
          assert_equal :revoke_to_org, result
        end
      end

      test "copilot disabled" do
        get_enterprise_owned_orgs.each do |test_case|
          # Trials dont care if copilot is disabled, it might have been an error
          next if test_case[:trial]

          enable_feature_flag(:copilot_revokable_access, test_case[:org].business) if test_case[:revokable]

          result = Copilot::OrganizationCleanupDecider.new(test_case[:org]).get_action

          if test_case[:revokable]
            assert_equal :revoke_to_org, result
          else
            assert_equal :clean, result
          end
        end
      end
    end
  end
end
