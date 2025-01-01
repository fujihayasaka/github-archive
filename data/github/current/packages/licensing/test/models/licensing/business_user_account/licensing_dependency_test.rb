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

    context "#can_emit_billing_message?" do
      test "returns true for metered plan business" do
        @business.customer.update metered_ghe: true
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_predicate @business.reload, :metered_plan?

        assert_predicate business_user_account, :can_emit_billing_message?
      end

      test "returns false for non-metered plan business" do
        business_user_account = create(:business_user_account, user: @member, business: @business)
        refute_predicate @business, :metered_plan?

        refute_predicate business_user_account, :can_emit_billing_message?
      end
    end

    context "#emit_added_license_billing_message" do
      test "publishes hydro event for added license billing" do
        Timecop.freeze("2024-02-02") do
          @business.customer.update metered_ghe: true
          business_user_account = create(:business_user_account, user: @member, business: @business)
          billing_message_usage_at = Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0)
          assert_predicate @business.reload, :metered_plan?
          assert_predicate business_user_account, :can_emit_billing_message?

          business_user_account.emit_added_license_billing_message
          assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 1)
          assert_hydro_published_partial({
            sku: "ghec_seats",
            quantity: 1.0,
            usage_at: billing_message_usage_at,
            source_uri: @billing_message_source_uri,
            entity: @billing_message_entity
          }, schema: "billingplatform.v1.Usage")
        end
      end

      test "emitted hydro events have unique UUIDs for unique timestamps, for the same user" do
        Timecop.freeze("2024-02-02") do
          @business.customer.update metered_ghe: true
          business_user_account = create(:business_user_account, user: @member, business: @business)

          business_user_account.emit_added_license_billing_message

          Timecop.travel(1.minute.from_now) do
            business_user_account.emit_added_license_billing_message
          end

          hydro_messages = hydro_messages(schema: "billingplatform.v1.Usage")
          usage_uuids = hydro_messages.map { |message| message[:usage_uuid] }
          refute_equal usage_uuids.first, usage_uuids.last
        end
      end

      test "logs info on emitted data for added license billing" do
        Timecop.freeze("2024-02-02") do
          @business.customer.update metered_ghe: true
          business_user_account = create(:business_user_account, user: @member, business: @business)
          assert_predicate @business.reload, :metered_plan?
          assert_predicate business_user_account, :can_emit_billing_message?

          expected_log = {
            "Body": "emitted data",
            "gh.business.ghec_seats": 1.0,
            "usage_at": Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
            "entity_customer_id": @business.customer_id,
            "entity_actor_id": @member.id,
          }

          assert_logged(**expected_log) do
            business_user_account.emit_added_license_billing_message
          end
        end
      end

      test "increments dogstats for added license billing" do
        @business.customer.update metered_ghe: true
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_predicate @business.reload, :metered_plan?
        assert_predicate business_user_account, :can_emit_billing_message?

        business_user_account.emit_added_license_billing_message
        assert_equal 1, GitHub.dogstats.increments("ghec_seats.billing_vnext.added").length
      end

      test "instruments business.emit_ghec_license_added event" do
        @business.customer.update metered_plan: true
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_predicate @business.reload, :metered_plan?
        assert_predicate business_user_account, :can_emit_billing_message?

        events = assert_performed_audit_entries(count: 1, only: "business.emit_ghec_license_added") do
          business_user_account.emit_added_license_billing_message
        end

        expected_payload = {
          action: "business.emit_ghec_license_added",
          business: @business.slug,
          business_id: @business.id,
          name: @business.name
        }

        assert_subset_hash expected_payload, events.first
      end
    end

    context "#emit_removed_license_billing_message" do
      test "publishes hydro event for removed license billing" do
        Timecop.freeze("2024-02-02") do
          @business.customer.update metered_ghe: true
          business_user_account = create(:business_user_account, user: @member, business: @business)
          billing_message_usage_at = Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0)
          assert_predicate @business.reload, :metered_plan?
          assert_predicate business_user_account, :can_emit_billing_message?

          business_user_account.emit_removed_license_billing_message
          assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 1)
          assert_hydro_published_partial({
            sku: "ghec_seats",
            quantity: -1.0,
            usage_at: billing_message_usage_at,
            source_uri: @billing_message_source_uri,
            entity: @billing_message_entity
          }, schema: "billingplatform.v1.Usage")
        end
      end

      test "logs info on emitted data for removed license billing" do
        Timecop.freeze("2024-02-02") do
          @business.customer.update metered_ghe: true
          business_user_account = create(:business_user_account, user: @member, business: @business)
          assert_predicate @business.reload, :metered_plan?
          assert_predicate business_user_account, :can_emit_billing_message?

          expected_log = {
            "Body": "emitted data",
            "gh.business.ghec_seats": -1.0,
            "usage_at": Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
            "entity_customer_id": @business.customer_id,
            "entity_actor_id": @member.id,
          }

          assert_logged(**expected_log) do
            business_user_account.emit_removed_license_billing_message
          end
        end
      end

      test "increments dogstats for removed license billing" do
        @business.customer.update metered_ghe: true
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_predicate @business.reload, :metered_plan?
        assert_predicate business_user_account, :can_emit_billing_message?

        business_user_account.emit_removed_license_billing_message
        assert_equal 1, GitHub.dogstats.increments("ghec_seats.billing_vnext.removed").length
      end

      test "instruments business.emit_ghec_license_removed event" do
        @business.customer.update metered_plan: true
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_predicate @business.reload, :metered_plan?
        assert_predicate business_user_account, :can_emit_billing_message?

        events = assert_performed_audit_entries(count: 1, only: "business.emit_ghec_license_removed") do
          business_user_account.emit_removed_license_billing_message
        end

        expected_payload = {
          action: "business.emit_ghec_license_removed",
          business: @business.slug,
          business_id: @business.id,
          name: @business.name
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end
end
