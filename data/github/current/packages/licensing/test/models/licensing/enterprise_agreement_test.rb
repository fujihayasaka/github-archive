# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::EnterpriseAgreementTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "validations" do
    test "requires agreement_id" do
      agreement = Licensing::EnterpriseAgreement.new
      refute agreement.valid?
      refute_empty agreement.errors[:agreement_id]
    end

    test "requires business" do
      agreement = Licensing::EnterpriseAgreement.new
      refute agreement.valid?
      refute_empty agreement.errors[:business]
    end

    test "requires category" do
      agreement = Licensing::EnterpriseAgreement.new
      refute agreement.valid?
      refute_empty agreement.errors[:category]
    end

    test "requires valid category" do
      assert_raises ArgumentError do
        Licensing::EnterpriseAgreement.new(category: "invalid")
      end
    end

    test "requires status" do
      agreement = Licensing::EnterpriseAgreement.new(status: nil)
      refute agreement.valid?
      refute_empty agreement.errors[:status]
    end

    test "requires valid status" do
      assert_raises ArgumentError do
        Licensing::EnterpriseAgreement.new(status: "invalid")
      end
    end

    test "requires 0 seats when not visual studio bundle agreement" do
      agreement = Licensing::EnterpriseAgreement.new(category: "github_enterprise_unified", seats: 10)
      refute agreement.valid?
      refute_empty agreement.errors[:seats]
    end
  end

  context "#agreement_id=" do
    test "strips out surrounding whitespace that is sometimes included (from copy-pasting the value from an external source)" do
      agreement = Licensing::EnterpriseAgreement.new(agreement_id: "\t     1234 abcd   \t   ")

      assert_equal "1234 abcd", agreement.agreement_id
    end

    test "does not blow up when an integer is assigned" do
      agreement = Licensing::EnterpriseAgreement.new(agreement_id: 123)

      assert_equal "123", agreement.agreement_id
    end

    test "does not blow up when `nil` is assigned" do
      agreement = Licensing::EnterpriseAgreement.new(agreement_id: nil)

      assert_nil agreement.agreement_id
    end
  end

  context "#sync_bundled_license_agreement_business" do
    test "queues Licensing::BundledLicenseAssignmentBusinessLinkingJob on create" do
      assert_enqueued_with(job: Licensing::BundledLicenseAssignmentBusinessLinkingJob) do
        create(:enterprise_agreement)
      end
    end

    test "queues Licensing::BundledLicenseAssignmentBusinessLinkingJob on update" do
      agreement = create(:enterprise_agreement)
      assert_enqueued_with(job: Licensing::BundledLicenseAssignmentBusinessLinkingJob) do
        agreement.update(agreement_id: "foo")
      end
    end
  end

  context "updates customer in billing platform" do
    test "job is queued when creating an enterprise agreement" do
      customer = create(:customer, :azure, metered_ghe: false, metered_via_azure: false, billing_type: "card")
      business = create(:business, customer: customer)
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        create(:enterprise_agreement, status: "active", business: business)

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer.reload])
      end

      # One enterprise agreement creation
      assert_dogstats_increment(1, "billing_enterprise_agreement.billing_platform_update_customer")

      # Creation enqueued
      assert_dogstats_increment(1, "billing_enterprise_agreement.billing_platform_update_customer_called")
    end

    test "job is queued when updating an enterprise agreement" do
      customer = create(:credit_card_customer, metered_ghe: false, metered_via_azure: false, billing_type: "card")
      business = create(:business, customer: customer)
      ended_enterprise_agreement = create(:enterprise_agreement, status: "ended", business: business)
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        ended_enterprise_agreement.status = "active"
        ended_enterprise_agreement.save!

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer])
      end

      # One enterprise agreement creation and one update
      assert_dogstats_increment(2, "billing_enterprise_agreement.billing_platform_update_customer")

      # Creation and update enqueued
      assert_dogstats_increment(2, "billing_enterprise_agreement.billing_platform_update_customer_called")
    end
  end
end if GitHub.billing_enabled?
