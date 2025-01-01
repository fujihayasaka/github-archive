# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::OrganizationCleanerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper

  context "perform" do
    # orgs either need to be deleted, archived or spammy to be cleaned up
    test "it does nothing for a cool org" do
      org = create(:credit_card_organization)
      Copilot::ErrorReporter.expects(:report!).never
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org.id, nil)
        end
      end
      assert_includes logs, "Organization exists"
    end

    test "it cleans nothing if the organization id didn't have copilot" do
      Copilot::ErrorReporter.expects(:report!).never
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::OrganizationCleaner.call(0, 0)
      end
    end

    context "archived" do
      test "it cleans up configuration if deleted" do
        Copilot::ErrorReporter.expects(:report!).never
        organization = create(:credit_card_organization)
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        co.enable_copilot!
        organization.set_archived(organization.admins.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        organization.set_archived(organization.admins.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seat assignments even when we do not have a customer object" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        org_id = organization.id
        organization.set_archived(organization.admins.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, nil)
        end
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        organization.set_archived(organization.admins.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization, state: "expired")
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.set_archived(organization.admins.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end
    end

    context "spammy" do
      test "it cleans up configuration if deleted" do
        Copilot::ErrorReporter.expects(:report!).never
        organization = create(:credit_card_organization)
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        Copilot::Organization.new(organization).enable_copilot!
        organization.update(spammy: true)

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.update(spammy: true)

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.update(spammy: true)

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization, state: "expired")
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.update(spammy: true)

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end
    end

    context "billing locked" do
      test "it cleans up configuration if billing locked" do
        Copilot::ErrorReporter.expects(:report!).never
        organization = create(:credit_card_organization)
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        Copilot::Organization.new(organization).enable_copilot!
        organization.disable!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.disable!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.disable!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization, state: "expired")
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.disable!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end
    end

    context "deleted" do
      test "it cleans up configuration if deleted" do
        Copilot::ErrorReporter.expects(:report!).never
        organization = create(:credit_card_organization)
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        co.enable_copilot!
        organization.destroy!
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization)
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end
    end

    context "no copilot for business" do
      test "it cleans up configuration if no cfb" do
        Copilot::ErrorReporter.expects(:report!).never
        organization = create(:credit_card_organization)
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end

        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization

        org_id = organization.id
        co = Copilot::Organization.new(organization)
        co.enable_copilot!
        co.disable_copilot!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end

        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        Copilot::Business.new(organization.business).disable_copilot!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization, state: "expired")
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(organization, reason).once

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
        end
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end

      test "does not clean up active trials" do
        trial = create(:copilot_business_trial, :organization)
        organization = trial.trialable
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        assert Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end

      test "does not clean up pending trials" do
        trial = create(:copilot_business_trial, :organization, state: :pending)
        organization = trial.trialable
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
        end
        assert Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end
    end

    context "is not .copilot_billable?" do
      test "it logs" do
        org = create(:copilot_for_business_enabled_organization)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

        copilot_org = Copilot::Organization.new(org)
        seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first)
        seat_assignment.convert_to_seats

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org.id, T.must(copilot_org.customer_for).id, reason)
          end
        end

        assert_includes logs, "Organization exists"
        assert_includes logs, "gh.copilot.is_billable=\"false\""
        refute Copilot::SeatAssignment.exists?(organization_id: org.id)
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org.id)
      end

      test "cleans up nothing if the org is billable" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        org = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(org)
        seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first)
        seat_assignment.convert_to_seats
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(org.id, T.must(copilot_org.customer_for).id)
        end

        refute_empty Copilot::Seat.for_organization(org)
      end
    end
  end
end if GitHub.copilot_enabled?
