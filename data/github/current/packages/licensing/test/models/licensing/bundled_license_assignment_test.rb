# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::BundledLicenseAssignmentTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @email = "email@example.com"
    @enterprise_agreement_number = "12345"
    @enterprise_agreement = create(:enterprise_agreement, :visual_studio_bundle, agreement_id: @enterprise_agreement_number)
    @business = @enterprise_agreement.business
  end

  context "validations" do
    test "enterprise agreement number is required" do
      assignment = Licensing::BundledLicenseAssignment.new
      assignment.valid?

      assert assignment.errors.key?(:enterprise_agreement_number)
    end

    test "email is required" do
      assignment = Licensing::BundledLicenseAssignment.new
      assignment.valid?

      assert assignment.errors.key?(:email)
    end

    test "subscription_id is required" do
      assignment = Licensing::BundledLicenseAssignment.new
      assignment.valid?

      assert assignment.errors.key?(:subscription_id)
    end

    test "subscription_id must be unique among non-revoked assignments" do
      existing_assignment = create(:licensing_bundled_license_assignment)
      assignment = Licensing::BundledLicenseAssignment.new(subscription_id: existing_assignment.subscription_id)
      assignment.valid?

      assert assignment.errors.key?(:subscription_id)

      assignment.revoked = true
      assignment.valid?

      refute assignment.errors.key?(:subscription_id)

      assignment.revoked = false
      existing_assignment.revoke!
      assignment.valid?

      refute assignment.errors.key?(:subscription_id)
    end

    test "revoked can't be nil" do
      assignment = Licensing::BundledLicenseAssignment.new(revoked: nil)
      assignment.valid?

      assert assignment.errors.key?(:revoked)
    end
  end

  context "#for_query" do
    test "returns scoped entries when query is blank" do
      assignment = create :licensing_bundled_license_assignment
      assert_equal [assignment], Licensing::BundledLicenseAssignment.for_query("  ")
      assert_equal [assignment], Licensing::BundledLicenseAssignment.for_query(nil)
    end

    test "returns assignments matching email" do
      matching = create :licensing_bundled_license_assignment, email: "matching@example.com"
      not_matching = create :licensing_bundled_license_assignment, email: "somethingelse@example.com"
      assert_equal [matching], Licensing::BundledLicenseAssignment.for_query("matching")
    end
  end

  context "after_commit callbacks" do
    test "queues a job to send VSS a status after creation" do
      assert_enqueued_with job: Licensing::SendVssStatusMessageJob do
        create(:licensing_bundled_license_assignment)
      end
    end

    test "queues a job to send VSS a status after update" do
      assignment = create(:licensing_bundled_license_assignment)

      assert_enqueued_with job: Licensing::SendVssStatusMessageJob do
        assignment.update(updated_at: 1.day.ago)
      end
    end
  end

  context "#handle_revoke" do
    test "sets revoked_at to time if revoked is true" do
      assignment = create(:licensing_bundled_license_assignment)
      refute assignment.revoked_at
      assignment.update(revoked: true)
      assert assignment.revoked_at
    end

    test "sets revoked_at to nil if revoked is false" do
      assignment = create(:licensing_bundled_license_assignment, revoked: true)
      assert assignment.revoked_at
      assignment.update(revoked: false)
      refute assignment.revoked_at
    end
  end

  context "setting a business on the assignment" do
    test "sets assigned_business_at to time if business_id is present" do
      assignment = create(:licensing_bundled_license_assignment)
      refute assignment.assigned_business_at
      assignment.update(business: create(:business))
      assert assignment.assigned_business_at
    end

    test "sets assigned_business_at to nil if business_id is not present" do
      assignment = create(:licensing_bundled_license_assignment, business: create(:business))
      assert assignment.assigned_business_at
      assignment.update(business: nil)
      refute assignment.assigned_business_at
    end

    test "queues SetUserFromBusinessOnBundledLicenseAssignmentJob on create if business_id is present" do
      assert_enqueued_with(job: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob) do
        create(:licensing_bundled_license_assignment, business: create(:business))
      end
    end

    test "does NOT queues SetUserFromBusinessOnBundledLicenseAssignmentJob on create if business_id is NOT present" do
      Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.expects(:perform_later).never
      create(:licensing_bundled_license_assignment)
    end
  end

  context "#handle_user_assignment" do
    test "sets assigned_user_at to timeif user_id is present" do
      assignment = create(:licensing_bundled_license_assignment)
      refute assignment.assigned_user_at
      assignment.update(user: create(:user))
      assert assignment.assigned_user_at
    end

    test "sets assigned_user_at to nil if user_id is present" do
      assignment = create(:licensing_bundled_license_assignment, user: create(:user))
      assert assignment.assigned_user_at
      assignment.update(user: nil)
      refute assignment.assigned_user_at
    end
  end

  test "for_enterprise_agreement" do
    enterprise_agreement = create(:enterprise_agreement)
    assignment = create(:licensing_bundled_license_assignment, enterprise_agreement_number: enterprise_agreement.agreement_id)
    unrelated_assignment = create(:licensing_bundled_license_assignment)
    assert_equal [assignment], Licensing::BundledLicenseAssignment.for_enterprise_agreement(enterprise_agreement.agreement_id)
  end

  context "#assigned_user?" do
    test "returns true when user is present" do
      assert create(:licensing_bundled_license_assignment, user: create(:user)).assigned_user?
    end

    test "returns false when user is not present" do
      refute create(:licensing_bundled_license_assignment).assigned_user?
    end
  end

  context "#revoke!" do
    test "revokes assignment and sends a status message to VSS" do
      assignment = create(:licensing_bundled_license_assignment)
      refute assignment.revoked?

      assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
        assignment.revoke!
      end

      assert assignment.revoked?
    end
  end

  context "Instrumentation" do
    test "Instruments create" do
      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.create") do
        create(:licensing_bundled_license_assignment)
      end
      bundled_assignment = Licensing::BundledLicenseAssignment.last

      expected_payload = {
        action: "bundled_license_assignment.create",
        bundled_license_assignment_id: T.must(bundled_assignment).id,
        email: T.must(bundled_assignment).email,
        enterprise_agreement_number: T.must(bundled_assignment).enterprise_agreement_number,
        subscription_id: T.must(bundled_assignment).subscription_id
      }

      assert event = events.pop, "bundled_license_assignment.create event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instruments revoke" do
      bundled_assignment = create(:licensing_bundled_license_assignment, email: "test@example.com")
      anonymized_email = SecureRandom.hex(32)

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.revoke") do
        bundled_assignment.revoke!(email: anonymized_email)
      end

      expected_payload = {
        action: "bundled_license_assignment.revoke",
        bundled_license_assignment_id: bundled_assignment.id,
        email: anonymized_email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        revoked: true
      }

      assert event = events.pop, "bundled_license_assignment.revoke event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instruments revoke with nil email" do
      bundled_assignment = create(:licensing_bundled_license_assignment)

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.revoke") do
        bundled_assignment.revoke!(email: nil)
      end

      expected_payload = {
        action: "bundled_license_assignment.revoke",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        revoked: true
      }

      assert event = events.pop, "bundled_license_assignment.revoke event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instruments assigned_user" do
      bundled_assignment = create(:licensing_bundled_license_assignment)
      user = create(:business).admins.first

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_user") do
        bundled_assignment.update(user: user)
      end

      expected_payload = {
        action: "bundled_license_assignment.assigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: user.id,
        user: user.display_login,
      }

      assert event = events.pop, "bundled_license_assignment.assigned_user event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instruments unassigned_user" do
      user = create(:business).admins.first
      bundled_assignment = create(:licensing_bundled_license_assignment, user: user)
      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.unassigned_user") do
        bundled_assignment.update(user: nil)
      end

      expected_payload = {
        action: "bundled_license_assignment.unassigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: user.id,
        user: user.display_login,
      }

      assert event = events.pop, "bundled_license_assignment.unassigned_user event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instruments unassigned_user and assigned_user on changed assignment" do
      old_user = create(:user)
      bundled_assignment = create(:licensing_bundled_license_assignment, user: old_user)
      user = create(:business).admins.first

      events = assert_performed_audit_entries(count: 2, only: ["bundled_license_assignment.assigned_user", "bundled_license_assignment.unassigned_user"]) do
        bundled_assignment.update(user: user)
      end

      expected_unassign_payload = {
        action: "bundled_license_assignment.unassigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: old_user.id,
        user: old_user.display_login,
      }

      expected_assign_payload = {
        action: "bundled_license_assignment.assigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: user.id,
        user: user.display_login,
      }

      assign_event = events.pop # unassign event should be first, assign event should be second
      assert assign_event, "bundled_license_assignment.assigned_user event was expected"
      assert_subset_hash expected_assign_payload, assign_event

      unasign_event = events.pop
      assert unasign_event, "bundled_license_assignment.unassigned_user event was expected"
      assert_subset_hash expected_unassign_payload, unasign_event

      assert events.empty?
    end

    test "Instruments assigned_business" do
      bundled_assignment = create(:licensing_bundled_license_assignment)
      business = create(:business)

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_business") do
        bundled_assignment.update(business: business)
      end

      expected_payload = {
        action: "bundled_license_assignment.assigned_business",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        business: business.name,
        business_id: business.id
      }

      assert event = events.pop, "bundled_license_assignment.assigned_business event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end

    test "Instrumentation include business if business is present" do
      business = create(:business)

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.create") do
        create(:licensing_bundled_license_assignment, business: business)
      end

      bundled_assignment = Licensing::BundledLicenseAssignment.last

      expected_payload = {
        action: "bundled_license_assignment.create",
        bundled_license_assignment_id: T.must(bundled_assignment).id,
        email: T.must(bundled_assignment).email,
        enterprise_agreement_number: T.must(bundled_assignment).enterprise_agreement_number,
        subscription_id: T.must(bundled_assignment).subscription_id,
        business: business.name,
        business_id: business.id
      }

      assert event = events.pop, "bundled_license_assignment.create event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end
  end

  context "send_creation_email on business create and update" do
    test "returns if there is no business" do
      assignment = create(:licensing_bundled_license_assignment, user: create(:user))
      BillingNotificationsMailer.expects(:bundled_license_assignment_created).never
      assignment.update(business: nil)
    end

    test "returns if there is a key set" do
      assignment = create(:licensing_bundled_license_assignment, user: create(:user))

      # rubocop:todo GitHub/DoNotUseGlobalKv
      Billing::Kv.store.setnx("bundled_license_assignment_creation_email_#{assignment.id}", "true")
      # rubocop:enable GitHub/DoNotUseGlobalKv
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert Billing::Kv.store.exists("bundled_license_assignment_creation_email_#{assignment.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv

      BillingNotificationsMailer.expects(:bundled_license_assignment_created).never
      assignment.update(business: @business)
    end

    test "sets a key on update business" do
      disable_feature_flag(:skip_bundled_license_assignment_email)

      assignment = create(:licensing_bundled_license_assignment, user: create(:user))

      BillingNotificationsMailer.expects(:bundled_license_assignment_created)
          .with(assignment)
          .returns(stub(deliver_later: nil))
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute Billing::Kv.store.exists("bundled_license_assignment_creation_email_#{assignment.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
      assignment.update(business: @business)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert Billing::Kv.store.exists("bundled_license_assignment_creation_email_#{assignment.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "sends an email once on update business" do
      disable_feature_flag(:skip_bundled_license_assignment_email)

      assignment = create(:licensing_bundled_license_assignment, user: create(:user))

      BillingNotificationsMailer.expects(:bundled_license_assignment_created)
          .with(assignment)
          .returns(stub(deliver_later: nil))
      assignment.update(business: @business)

      BillingNotificationsMailer.expects(:bundled_license_assignment_created).never
      assignment.update(business: @business)
    end

    test "does not send an email once on update business if the skip feature flag is enabled" do
      enable_feature_flag(:skip_bundled_license_assignment_email)

      assignment = create(:licensing_bundled_license_assignment, user: create(:user))

      BillingNotificationsMailer.expects(:bundled_license_assignment_created).never
    end
  end

  context "Run callbacks properly upon changes happened in a transaction" do
    test "#user assignment callbacks" do
      old_user = create(:user)
      bundled_assignment = create(:licensing_bundled_license_assignment, user: old_user)

      new_user = create(:business).admins.first

      events = assert_performed_audit_entries(count: 2, only: ["bundled_license_assignment.assigned_user", "bundled_license_assignment.unassigned_user"]) do
        Licensing::BundledLicenseAssignment.transaction do
          bundled_assignment.update(user: new_user)

          bundled_assignment.save
        end
      end

      expected_unassign_payload = {
        action: "bundled_license_assignment.unassigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: old_user.id,
        user: old_user.display_login,
      }

      expected_assign_payload = {
        action: "bundled_license_assignment.assigned_user",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        user_id: new_user.id,
        user: new_user.display_login,
      }

      assign_event = events.pop # unassign event should be first, assign event should be second
      assert assign_event, "bundled_license_assignment.assigned_user event was expected"
      assert_subset_hash expected_assign_payload, assign_event

      unasign_event = events.pop
      assert unasign_event, "bundled_license_assignment.unassigned_user event was expected"
      assert_subset_hash expected_unassign_payload, unasign_event

      assert events.empty?
    end

    test "#business assginment callbacks" do
      bundled_assignment = create(:licensing_bundled_license_assignment)
      business = create(:business)

      events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_business") do
        Licensing::BundledLicenseAssignment.transaction do
          bundled_assignment.update(business: business)

          bundled_assignment.save
        end
      end

      expected_payload = {
        action: "bundled_license_assignment.assigned_business",
        bundled_license_assignment_id: bundled_assignment.id,
        email: bundled_assignment.email,
        enterprise_agreement_number: bundled_assignment.enterprise_agreement_number,
        subscription_id: bundled_assignment.subscription_id,
        business: business.name,
        business_id: business.id
      }

      assert event = events.pop, "bundled_license_assignment.assigned_business event was expected"
      assert events.empty?
      assert_subset_hash expected_payload, event
    end
  end
end if GitHub.billing_enabled?
