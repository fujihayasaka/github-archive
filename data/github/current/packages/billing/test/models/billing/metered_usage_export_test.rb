# typed: true
# frozen_string_literal: true

require "test_helper"

class MeteredUsageExportTest < GitHub::BillingTestCase
  setup do
    @presigner_mock = mock("Aws::S3::Presigner")
    Aws::S3::Presigner.stubs(:new).returns(@presigner_mock)
  end

  context "#generate_expiring_url" do
    test "returns a signed S3 url" do
      @presigner_mock.expects(:presigned_url).with(
        :get_object,
        bucket: "github-billing-report-exports",
        key: "testfilename.csv",
        expires_in: 60.minutes.to_i,
      ).returns("https://realaws.localhost/testfilename.csv")

      metered_usage_export = create(:metered_usage_export, filename: "testfilename.csv")
      metered_usage_export.stubs(:presigner).returns(@presigner_mock)

      assert_equal "https://realaws.localhost/testfilename.csv", metered_usage_export.generate_expiring_url
    end
  end

  context "#azure_generate_expiring_url" do
    test "returns a signed azure url" do
      metered_usage_export = create(:metered_usage_export, filename: "testfilename.csv", is_azure_blob_storage: true)
      GitHub.stubs(:metered_billing_azure_storage_account_name).returns("storage-account-name")
      Billing::Azure::SharedAccessSignatureUrlGenerator.expects(:generate_sas_url).returns("https://storage-account-name.blob.core.windows.net/billing-metered-exports-reports/testfilename?fdsfs23r2d&sp=")
      assert_equal "https://storage-account-name.blob.core.windows.net/billing-metered-exports-reports/testfilename?fdsfs23r2d&sp=", metered_usage_export.generate_expiring_url
    end
  end

  context "#get_url" do
    test "returns an enterprise url when billable owner is a business" do
      customer = create(:customer)
      billable_owner = create(:business, customer: customer)
      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner)

      assert_equal(
        "https://github.com/enterprises/#{billable_owner.slug}/settings/metered_exports/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end

    test "returns an organization url when billable owner is a organization" do
      customer = create(:customer)
      billable_owner = create(:organization, customer: customer)
      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner)

      assert_equal(
        "https://github.com/organizations/#{billable_owner.display_login}/billing/metered_exports/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end

    test "returns a user url when billable owner is a user" do
      customer = create(:customer)
      billable_owner = create(:user, customer: customer)
      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner)

      assert_equal(
        "https://github.com/account/billing/metered_exports/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end

    test "returns correct url when requester is a enterprise user and the export is on Azure" do
      customer = create(:customer)
      billable_owner = create(:business, customer: customer)
      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner, is_azure_blob_storage: true)

      assert_equal(
        "https://github.com/enterprises/#{billable_owner.slug}/billing/usage_report/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end

    test "returns correct stafftools url when requester is a stafftools user and the export is on Azure" do
      customer = create(:customer)
      billable_owner = create(:business, customer: customer)
      staff_user = create(:staff_admin_user)
      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner, requester: staff_user, is_azure_blob_storage: true)

      assert_equal(
        "https://admin.github.com/stafftools/enterprises/#{billable_owner.slug}/billing/usage_report/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end

    test "returns correct multitenant stafftools url when requester is a stafftools user and the export is on Azure", skip_unless: :multi_tenant_enterprise? do
      stafftools_tenant = create :business, :enterprise_managed, slug: "stafftoolswus2", name: "stafftoolswus2"
      stafftools_emu = create :emu, business: stafftools_tenant
      emu_admin = create(:emu, :owner)
      emu_biz   = emu_admin.enterprise_managed_business
      customer = create(:customer, business: emu_biz)
      billable_owner = create(:business, customer: customer)

      metered_usage_export = create(:metered_usage_export, billable_owner: billable_owner, requester: stafftools_emu, is_azure_blob_storage: true)

      GitHub::CurrentTenant.set(stafftools_tenant)
      GitHub.stubs(:host_name).returns("ghe.com")

      assert_equal(
        "https://#{stafftools_tenant.slug}.ghe.com/stafftools/enterprises/#{billable_owner.slug}/billing/usage_report/#{metered_usage_export.id}",
        metered_usage_export.get_url
      )
    end
  end
end
