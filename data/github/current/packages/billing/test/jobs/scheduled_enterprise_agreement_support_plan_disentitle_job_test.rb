# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScheduledEnterpriseAgreementSupportPlanDisentitleJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  unless GitHub.single_business_environment?
    setup do
      GitHub.stubs(:braavos_support_entitlement_url).returns("http://braavos.test")
      GitHub.stubs(:braavos_support_entitlement_hmac).returns("nevermind")
      GitHub.flipper[:enterprise_agreement_support_plan_disentitle_job].enable
      GitHub.flipper[:enterprise_agreement_support_plan_disentitle_job_live_run].disable
      stub_domain("braavos.test")
    end

    teardown do
      GitHub.flipper[:enterprise_agreement_support_plan_disentitle_job].disable
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: ScheduledEnterpriseAgreementSupportPlanDisentitleJob
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: ScheduledEnterpriseAgreementSupportPlanDisentitleJob
    end

    test "runs in the support_plan_entitlement queue" do
      assert_enqueued_jobs(1, queue: :support_plan_entitlement) do
        ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_later
      end
    end

    context "enterprise_agreement_support_plan_disentitle_job feature is disabled" do
      test "the job does not run" do
        GitHub.flipper[:enterprise_agreement_support_plan_disentitle_job].disable

        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)
        business.microsoft_support_plan = "premium_unified"
        business.save

        SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_disentitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
        end
      end
    end

    test "ignores business without a harmony support plan" do
      customer = create(:credit_card_customer, metered_ghe: false)
      business = create(:business, customer: customer)

      SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
      end
    end

    test "ignores metered customers" do
      customer = create(:customer, metered_plan: true)
      business = create(:business, customer: customer)
      business.microsoft_support_plan = "premium_unified"
      business.save

      SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
      end
    end

    context "business is entitled" do
      context "active associated enterprise agreement with unified support" do
        test "does not create events or unset support plan" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          enterprise_agreement = create(:enterprise_agreement, business: business)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [
              condition: "Active Contract",
              type: "Premier",
              packages: [{ serviceOfferingId: 1283 }],
              tpid: "12345",
            ],
            eans: [],
            salesforce_account_id: "salesforce-id"
          }).once

          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", anything)
            .never

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end

          assert_equal "premium_unified", business.reload.microsoft_support_plan
        end
      end

      context "active enterprise agreements in salesforce with unified support" do
        test "does not create events or unset support plan" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          enterprise_agreement = create(:enterprise_agreement)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [
              condition: "Active Contract",
              type: "Premier",
              packages: [{ serviceOfferingId: 1283 }],
              tpid: "12345",
            ],
            eans: [enterprise_agreement.agreement_id],
            salesforce_account_id: "salesforce-id"
          }).once

          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", anything)
            .never

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end

          assert_equal "premium_unified", business.reload.microsoft_support_plan
        end
      end
    end

    context "business is not entitled" do
      context "braavos returns no response" do
        test "unsets the microsoft support plan and creates an event" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          enterprise_agreement = create(:enterprise_agreement)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea)
            .with(id: business.id).returns(nil).once

          Licensing::EnterpriseAgreement.expects(:where).never
          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", {
              business: business,
              previous_support_plan: "premium_unified",
              salesforce_account_id: nil
            })

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end

      context "no active agreements returned from braavos" do
        test "unsets the microsoft support plan and creates an event" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          enterprise_agreement = create(:enterprise_agreement)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [],
            eans: [enterprise_agreement.agreement_id],
            salesforce_account_id: "salesforce-id"
          }).once

          Licensing::EnterpriseAgreement.expects(:where).never
          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", {
              business: business,
              previous_support_plan: "premium_unified",
              salesforce_account_id: "salesforce-id"
            })

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end

      context "no agreements with unified support returned from braavos" do
        test "unsets the microsoft support plan and creates an event" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          enterprise_agreement = create(:enterprise_agreement)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [
              {
                condition: "Active Contract",
                type: "Premier",
                packages: [{ serviceOfferingId: 1010 }],
                tpid: "54321"
              }
            ],
            eans: [enterprise_agreement.agreement_id],
            salesforce_account_id: "salesforce-id"
          }).once

          Licensing::EnterpriseAgreement.expects(:where).never
          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", {
              business: business,
              previous_support_plan: "premium_unified",
              salesforce_account_id: "salesforce-id"
            })

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end

      context "no active enterprise agreements in github systems" do
        test "unsets the microsoft support plan and creates an event" do
          customer = create(:customer, :invoiced, metered_plan: false)
          business = create(:business, customer: customer)
          business.microsoft_support_plan = "premium_unified"
          business.save

          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [
              {
                condition: "Active Contract",
                type: "Premier",
                packages: [{ serviceOfferingId: 1283 }],
                tpid: "54321"
              }
            ],
            eans: ["12345"],
            salesforce_account_id: "salesforce-id"
          }).once

          GlobalInstrumenter.expects(:instrument)
            .with("microsoft_enterprise_agreement.support_disentitlement", {
              business: business,
              previous_support_plan: "premium_unified",
              salesforce_account_id: "salesforce-id"
            })

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end

      test "handles the case where a config entry exists for a deleted account" do
        customer = create(:credit_card_customer, metered_ghe: false)
        business = create(:business, customer: customer)
        business.microsoft_support_plan = "premium_unified"
        business.save

        business.soft_delete!

        SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
        end
      end

      test "rescues from SupportEntitlement::Braavos::Client::ApiError" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        business.microsoft_support_plan = "premium_unified"
        business.save

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).raises(SupportEntitlement::Braavos::Client::ApiError, "API error")

        expected_keys = {
          "SeverityText": "ERROR",
          "exception.type": "SupportEntitlement::Braavos::Client::ApiError",
          "exception.message": "API error",
          "Body": "Error fetching agreements for enterprise",
          "fn": "ScheduledEnterpriseAgreementSupportPlanDisentitleJob.process_batch",
          "business_id": business.id,
        }

        GitHub.dogstats.expects(:increment).at_least_once
        GitHub.dogstats.expects(:increment).with("scheduled_enterprise_agreement_support_plan_disentitle_job.error", tags: ["error:SupportEntitlement::Braavos::Client::ApiError"])

        assert_nothing_raised do
          assert_logged(**expected_keys) do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end

      test "unsets the microsoft support plan when the live run flag is set" do
        GitHub.flipper[:enterprise_agreement_support_plan_disentitle_job_live_run].enable

        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        business.microsoft_support_plan = "premium_unified"
        business.save

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea)
            .with(id: business.id).returns(nil).once

        expected_keys = {
          "SeverityText": "INFO",
          "Body": "Unset Microsoft Support Plan for Enterprise",
          "fn": "ScheduledEnterpriseAgreementSupportPlanDisentitleJob.unset_microsoft_support_plan",
          "business_id": business.id,
          "previous_support_plan": "premium_unified"
        }

        GitHub.dogstats.expects(:increment).at_least_once
        GitHub.dogstats.expects(:increment).with(
          "scheduled_enterprise_agreement_support_plan_disentitle_job.unset_microsoft_support_plan"
        )

        assert_nothing_raised do
          assert_logged(**expected_keys) do
            ScheduledEnterpriseAgreementSupportPlanDisentitleJob.perform_now
          end
        end
      end
    end
  end
end
