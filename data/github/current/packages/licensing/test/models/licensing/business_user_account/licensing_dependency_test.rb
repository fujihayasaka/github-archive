# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class Licensing::BusinessUserAccount::LicensingDependencyTest < GitHub::TestCase
    include AuditLog::IntegrationTestHelpers
    include DogstatsTestHelpers
    include GitHub::LoggerHelper
    include HydroTestHelpers

    fixtures do
      @site_admin = create :staff_admin_user
      @admin = create :user, login: "business-admin"
      @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @admin
      @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
      @member = create :user
      @shared_member = create :user
      @org1.add_member @shared_member
      @org2.add_member @admin
      @org2.add_member @member
      @org2.add_member @shared_member
      @org2.publicize_member @shared_member

      @business = create :business, owners: [@admin]

      @admin = @business.admins.first

      @billing_message_source_uri = GlobalID.create(@business.customer).to_s
      @billing_message_entity = { customer_id: @business.customer.id, actor_id: @member.id }
    end

    context "licensing snapshots" do
      test "publishes license snapshot events when the account is created, updated, and destroyed" do
        Timecop.freeze("2024-02-02") do
          perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
            business_user_account = create(:business_user_account, user: @member, business: @business)

            assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")

            business_user_account.update(updated_at: 1.year.from_now)

            assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")

            business_user_account.destroy

            assert_hydro_messages(count: 3, schema: "github.billing.v0.LicenseSnapshot")
          end
        end
      end
    end

    context "bundled license assignments", skip_enterprise: true do
      test "queues Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob if business has a volume license" do
        business = create(:business, :volume_licensed, seats: 1)
        assert_enqueued_with job: Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob, queue: "licensing" do
          create :business_user_account, user: @member, business: business
        end
      end
    end
  end
end
