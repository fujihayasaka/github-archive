# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScheduledEnterpriseAgreementSupportPlanEntitleJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  unless GitHub.single_business_environment?
    setup do
      GitHub.stubs(:braavos_support_entitlement_url).returns("http://braavos.test")
      GitHub.stubs(:braavos_support_entitlement_hmac).returns("nevermind")
      GitHub.flipper[:enterprise_agreement_support_plan_sync_job].enable
      GitHub.flipper[:enterprise_agreement_support_plan_sync_job_live_run].disable
      stub_domain("braavos.test")
    end

    teardown do
      GitHub.flipper[:enterprise_agreement_support_plan_sync_job].disable
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: ScheduledEnterpriseAgreementSupportPlanEntitleJob
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: ScheduledEnterpriseAgreementSupportPlanEntitleJob
    end

    test "runs in the support_plan_entitlement queue" do
      assert_enqueued_jobs(1, queue: :support_plan_entitlement) do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_later
      end
    end

    context "business is entitled to harmony support" do
      test "creates the appropriate events" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)
        business.microsoft_support_plan = "premium_unified"
        business.save

        service_offering_id_to_premium_plan = {
          1579 => "premium_unified",
          1279 => "premium_premier",
          828 => "premium_premier_psfp",
          1158 => "premium_premier_asfp",
        }

        service_offering_id_to_premium_plan.each do |service_offering_id, premium_plan|
          SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
            agreements: [
              packages: [{ serviceOfferingId: service_offering_id, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "12345",
              customerName: "Customer 12345"
            ],
            eans: [enterprise_agreement.agreement_id, "11111"],
            salesforce_account_id: "salesforce-id"
          }).once

          GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
            business: business,
            support_plan: premium_plan,
            previous_support_plan: "premium_unified",
            tpid: "12345",
            eans: [enterprise_agreement.agreement_id],
            salesforce_account_id: "salesforce-id",
            start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
            end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
            customer_name: "Customer 12345"
          }).once

          assert_nothing_raised do
            ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
          end
        end
      end

      test "ignores customers with existing unsupported support plans" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)
        business.microsoft_support_plan = "premium_plus_engineering_direct"
        business.save

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            packages: [{ serviceOfferingId: 1283, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          ],
          eans: [enterprise_agreement.agreement_id, "11111"],
          salesforce_account_id: "salesforce-id",
          start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
          end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
          customer_name: "Customer 12345"
        }).once

        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "only queries configuration_entries once in a batch" do
        10.times.each do
          customer = create(:customer, :invoiced, metered_plan: false)
          create(:business, customer: customer)
        end

        enterprise_agreement = create(:enterprise_agreement, business: create(:business))

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).returns({
            agreements: [
              packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "12345",
              customerName: "Customer 12345"
            ],
            eans: [enterprise_agreement.agreement_id, "11111"],
            salesforce_account_id: "salesforce-id"
          })

        GlobalInstrumenter.expects(:instrument)
          .with("microsoft_enterprise_agreement.support_entitlement", anything)
          .times(11)

        _, queries = log_queries do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end

        assert_equal 1, queries.count { |q| /FROM `?configuration_entries`?/ =~ q.sql }
      end

      test "only queries for enterprise licenses if the agreements include support offerings" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)

        customer = create(:customer, :invoiced, metered_plan: false)
        business_with_no_support = create(:business, customer: customer)

        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          ],
          eans: [enterprise_agreement.agreement_id, "11111"],
          salesforce_account_id: "salesforce-id"
        }).once

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business_with_no_support.id).returns({
          agreements: [
            packages: [{ serviceOfferingId: 5000, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "54321",
            customerName: "Customer 54321"
          ],
          eans: [enterprise_agreement.agreement_id, "222222"],
          salesforce_account_id: "salesforce-id-1"
        }).once

        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).once

        _, queries = log_queries do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end

        # Query 1: Lightweight query to check if there are any records
        # Query 2: Actual select to fetch the agreements
        assert_equal 2, queries.count { |q| /FROM `?enterprise_agreements`?/ =~ q.sql }
      end

      test "entitles with the greater of available support plans" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [
                { serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" },
                { serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "12345",
              customerName: "Customer 12345"
            }
          ],
          eans: [enterprise_agreement.agreement_id, "11111"],
          salesforce_account_id: "salesforce-id"
        }).once

        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
          business: business,
          support_plan: "premium_unified",
          previous_support_plan: nil,
          tpid: "12345",
          eans: [enterprise_agreement.agreement_id],
          salesforce_account_id: "salesforce-id",
          start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
          end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
          customer_name: "Customer 12345"
        }).once

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "entitles with the greater agreement" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "54321",
              customerName: "Customer 54321"
            },
            {
              packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "12345",
              customerName: "Customer 12345"
            }
          ],
          eans: [enterprise_agreement.agreement_id, "11111"],
          salesforce_account_id: "salesforce-id"
        }).once

        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
          business: business,
          support_plan: "premium_unified",
          previous_support_plan: nil,
          tpid: "54321",
          eans: [enterprise_agreement.agreement_id],
          salesforce_account_id: "salesforce-id",
          start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
          end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
          customer_name: "Customer 54321"
        }).once

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    test "falls back to associated enterprise agreements if none are found from the API" do
      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)
      enterprise_agreement = create(:enterprise_agreement, business: business)

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
        agreements: [
          {
            packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "54321",
            customerName: "Customer 54321"
          },
          {
            packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          }
        ],
        eans: [],
        salesforce_account_id: "salesforce-id"
      }).once

      GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
        business: business,
        support_plan: "premium_unified",
        previous_support_plan: nil,
        tpid: "54321",
        eans: [enterprise_agreement.agreement_id],
        salesforce_account_id: "salesforce-id",
        start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
        end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
        customer_name: "Customer 54321"
      }).once

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
      end
    end

    test "falls back to associated enterprise agreements if the ones returned from the API are not active" do
      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)
      enterprise_agreement = create(:enterprise_agreement, business: business)

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
        agreements: [
          {
            packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "54321",
            customerName: "Customer 54321"
          },
          {
            packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          }
        ],
        eans: ["11111"],
        salesforce_account_id: "salesforce-id"
      }).once

      GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
        business: business,
        support_plan: "premium_unified",
        previous_support_plan: nil,
        tpid: "54321",
        eans: [enterprise_agreement.agreement_id],
        salesforce_account_id: "salesforce-id",
        start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
        end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
        customer_name: "Customer 54321"
      }).once

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
      end
    end

    test "calculates the start and end date based on the entire support period accross packages" do
      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)
      enterprise_agreement = create(:enterprise_agreement, business: business)

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
        agreements: [
          {
            packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          },
          {
            packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2199-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          },
          {
            packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2199-10-01T00:00:00" }],
            tpid: "12345",
            customerName: "Customer 12345"
          }
        ],
        eans: ["11111"],
        salesforce_account_id: "salesforce-id"
      }).once

      GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
        business: business,
        support_plan: "premium_unified",
        previous_support_plan: nil,
        tpid: "12345",
        eans: [enterprise_agreement.agreement_id],
        salesforce_account_id: "salesforce-id",
        start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
        end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2199-10-01T00:00:00").to_i),
        customer_name: "Customer 12345"
      }).once

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
      end
    end

    context "business is not entitled to harmony support" do
      test "handles no active eans" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [{ serviceOfferingId: 1579, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "54321",
              customer_name: "Customer 54321"
            },
            {
              packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "12345",
              customer_name: "Customer 12345"
            }
          ],
          eans: ["11111"],
          salesforce_account_id: "salesforce-id"
        }).once


        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "handles no agreements with support entitlements" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [{ serviceOfferingId: 1010, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "54321",
              customer_name: "Customer 54321"
            }
          ],
          eans: [enterprise_agreement.agreement_id],
          salesforce_account_id: "salesforce-id"
        }).once


        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "handles bad dates from the api" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [{ serviceOfferingId: 1283, startDate: "", endDate: "" }],
              tpid: "54321",
              customerName: "Customer 54321"
            }
          ],
          eans: [enterprise_agreement.agreement_id],
          salesforce_account_id: "salesforce-id"
        }).once

        expected_keys = {
          "Body": "invalid date passed",
          "fn": "MicrosoftEnterpriseAgreement.earliest_and_latest_package_dates_by_tpid",
          "business_id": business.id,
        }

        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
          business: business,
          support_plan: "premium_unified",
          previous_support_plan: nil,
          tpid: "54321",
          eans: [enterprise_agreement.agreement_id],
          salesforce_account_id: "salesforce-id",
          start_date: nil,
          end_date: nil,
          customer_name: "Customer 54321"
        }).once

        assert_nothing_raised do
          assert_logged(**expected_keys) do
            ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
          end
        end
      end

      test "handles agreements not found" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns(nil).once

        Licensing::EnterpriseAgreement.expects(:where).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "handles no eans found" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [
            {
              packages: [{ serviceOfferingId: 1010, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
              tpid: "54321",
              customer_name: "Customer 54321"
            }
          ],
          eans: [],
          salesforce_account_id: "salesforce-id"
        }).once

        Licensing::EnterpriseAgreement.expects(:where).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end

      test "handles no agreements found" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)

        SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
          agreements: [],
          eans: ["12345"],
          salesforce_account_id: "salesforce-id"
        }).once

        Licensing::EnterpriseAgreement.expects(:where).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    test "rescues from SupportEntitlement::Braavos::Client::ApiError" do
      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).raises(SupportEntitlement::Braavos::Client::ApiError, "API error")

      expected_keys = {
        "SeverityText": "ERROR",
        "exception.type": "SupportEntitlement::Braavos::Client::ApiError",
        "exception.message": "API error",
        "Body": "Error fetching agreements for enterprise",
        "fn": "ScheduledEnterpriseAgreementSupportPlanEntitleJob.process_batch",
        "business_id": business.id,
      }

      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("scheduled_enterprise_agreement_support_plan_entitle_job.error", tags: ["error:SupportEntitlement::Braavos::Client::ApiError"])

      assert_nothing_raised do
        assert_logged(**expected_keys) do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    test "logs info when fetching the next batch of enterprises" do
      expected_keys = {
        "SeverityText": "INFO",
        "Body": "Fetching the next batch of enterprises",
        "fn": "ScheduledEnterpriseAgreementSupportPlanEntitleJob.next_batch",
        "offset_item_id": 0
      }
      assert_logged(**expected_keys) do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.new.next_batch
      end
    end

    test "updates the microsoft support plan when the live run flag is set and the support plans are different" do
      GitHub.flipper[:enterprise_agreement_support_plan_sync_job_live_run].enable

      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)
      enterprise_agreement = create(:enterprise_agreement, business: business)

      business.microsoft_support_plan = "premium_unified"
      business.save

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
        agreements: [
          packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
          tpid: "12345",
          customerName: "Customer 54321"
        ],
        eans: [enterprise_agreement.agreement_id, "11111"],
        salesforce_account_id: "salesforce-id"
      }).once

      GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
        business: business,
        support_plan: "premium_premier",
        previous_support_plan: "premium_unified",
        tpid: "12345",
        eans: [enterprise_agreement.agreement_id],
        salesforce_account_id: "salesforce-id",
        start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
        end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
        customer_name: "Customer 54321"
      }).once

      expected_keys = {
        "SeverityText": "INFO",
        "Body": "Updated Microsoft Support Plan for Enterprise",
        "fn": "ScheduledEnterpriseAgreementSupportPlanEntitleJob.update_microsoft_support_plan",
        "business_id": business.id,
        "support_plan": "premium_premier",
        "previous_support_plan": "premium_unified"
      }

      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with(
        "scheduled_enterprise_agreement_support_plan_entitle_job.microsoft_support_plan_updated",
        tags: ["plan:premium_premier"]
      )

      assert_nothing_raised do
        assert_logged(**expected_keys) do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    test "does not update the microsoft support plan when the live run flag is set and the support plans are the same" do
      GitHub.flipper[:enterprise_agreement_support_plan_sync_job_live_run].enable

      customer = create(:customer, :invoiced, metered_plan: false)
      business = create(:business, customer: customer)
      enterprise_agreement = create(:enterprise_agreement, business: business)

      business.microsoft_support_plan = "premium_premier"
      business.save

      SupportEntitlement::Braavos::Client.stubs(:check_entitlements_by_ea).with(id: business.id).returns({
        agreements: [
          packages: [{ serviceOfferingId: 1279, startDate: "2000-10-01T00:00:00", endDate: "2100-10-01T00:00:00" }],
          tpid: "12345",
          customerName: "Customer 12345"
        ],
        eans: [enterprise_agreement.agreement_id, "11111"],
        salesforce_account_id: "salesforce-id"
      }).once

      GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", {
        business: business,
        support_plan: "premium_premier",
        previous_support_plan: "premium_premier",
        tpid: "12345",
        eans: [enterprise_agreement.agreement_id],
        salesforce_account_id: "salesforce-id",
        start_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2000-10-01T00:00:00").to_i),
        end_date: Google::Protobuf::Timestamp.new(seconds: DateTime.parse("2100-10-01T00:00:00").to_i),
        customer_name: "Customer 12345"
      }).once

      expected_keys = {
        "Body": "Updated Microsoft Support Plan for Enterprise",
        "fn": "ScheduledEnterpriseAgreementSupportPlanEntitleJob.update_microsoft_support_plan",
        "business_id": business.id,
        "support_plan": "premium_premier",
        "previous_support_plan": "premium_premier"
      }

      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with(
        "scheduled_enterprise_agreement_support_plan_entitle_job.microsoft_support_plan_updated",
        tags: ["plan:premium_premier"]
      ).never

      assert_nothing_raised do
        refute_logged(**expected_keys) do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    test "ignores metered customers" do
      customer = create(:customer, :metered_ghe)
      business = create(:business, customer: customer)

      SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
      end
    end

    test "ignores credit card billed customers" do
      customer = create(:credit_card_customer, metered_ghe: false)
      business = create(:business, customer: customer)

      SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never

      assert_nothing_raised do
        ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
      end
    end

    context "enterprise_agreement_support_plan_sync_job feature is disabled" do
      test "the job does not run" do
        GitHub.flipper[:enterprise_agreement_support_plan_sync_job].disable

        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end

    context "does not run for staff owned accounts" do
      test "the job does not run" do
        customer = create(:customer, :invoiced, metered_plan: false)
        business = create(:business, :staff_owned, customer: customer)
        enterprise_agreement = create(:enterprise_agreement, business: business)

        SupportEntitlement::Braavos::Client.expects(:check_entitlements_by_ea).never
        GlobalInstrumenter.expects(:instrument).with("microsoft_enterprise_agreement.support_entitlement", anything).never

        assert_nothing_raised do
          ScheduledEnterpriseAgreementSupportPlanEntitleJob.perform_now
        end
      end
    end
  end
end
