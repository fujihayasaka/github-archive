# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/missing_record_helper"

class Copilot::OrganizationCleanerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include MissingRecordHelper

  def assert_cleanup(&block)
    Copilot::ErrorReporter.expects(:report!).never
    organization = create(:credit_card_organization)
    org_id = organization.id
    co = Copilot::Organization.new(organization)
    co.enable_copilot!

    yield organization if block_given?

    ActiveRecord::Base.connected_to(role: :reading) do
      Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
    end

    refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
    refute Copilot::SeatAssignment.exists?(organization_id: org_id)
    refute Copilot::Seat.exists?(organization_id: org_id)
  end

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

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
      refute_includes logs, "Revoking copilot seat access for organization"
    end

    test "it cleans nothing if the organization id didn't have copilot" do
      Copilot::ErrorReporter.expects(:report!).never
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::OrganizationCleaner.call(0, 0)
        end
      end

      refute_includes logs, "Revoking copilot seat access for organization"
    end

    context "deleted" do
      test "it cleans up all the things when soft_deleted" do
        logs = capture_logs do
          assert_cleanup do |organization|
            organization.soft_delete!
          end
        end
        refute_includes logs, "Revoking copilot seat access for organization"
      end
    end

    context "archived" do
      test "it cleans up configuration if archived" do
        Copilot::ErrorReporter.expects(:report!).never

        organization = create(:credit_card_organization)

        org_id = organization.id
        co = Copilot::Organization.new(organization)
        co.enable_copilot!
        organization.set_archived(organization.admins.first)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
        refute_includes logs, "Revoking copilot seat access for organization"
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        organization.set_archived(organization.admins.first)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seat assignments even when we do not have a customer object" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        org_id = organization.id
        organization.set_archived(organization.admins.first)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, nil)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        organization.set_archived(organization.admins.first)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization, state: "expired")
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.set_archived(organization.admins.first)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end

      test "it revokes seat assignments to enterprise when copilot_revokable_access is enabled" do
        enable_feature_flag(:copilot_revokable_access)
        ::Organization.any_instance.stubs(:archived?).returns(true)

        org = create(:copilot_for_business_enabled_organization)
        team_user = create(:user)
        other_user = create(:user)

        org.add_member(team_user)
        org.add_member(other_user)

        team = create(:team, organization: org)
        team.add_member(team_user)

        create(:copilot_seat_assignment, owner: org, assignable: team, assigning_user: org.admins.first).convert_to_seats
        create(:copilot_seat_assignment, owner: org, assignable: other_user, assigning_user: org.admins.first).convert_to_seats

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org.id, nil)
          end
        end

        Copilot::SeatAssignment.all.each do |assignment|
          assert assignment.access_revoked?
          assert assignment.pending_cancellation?
          assert_equal "Business", assignment.owner_type
          assert_equal org.business.id, assignment.owner_id
        end

        assert_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        seat_assignment = create(:copilot_seat_assignment, :organization)
        organization = seat_assignment.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::SeatAssignment.exists?(organization_id: org_id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        organization = seat.organization
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::Seat.exists?(organization_id: org_id)
      end

      test "it cleans up trials" do
        Copilot::ErrorReporter.expects(:report!).never
        trial = create(:copilot_business_trial, :organization)
        organization = trial.trialable
        co = Copilot::Organization.new(organization)
        org_id = organization.id
        organization.destroy!

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id, reason)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end

      test "does not clean up active trials" do
        trial = create(:copilot_business_trial, :organization)
        organization = trial.trialable
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        assert Copilot::BusinessTrial.exists?(trialable_id: org_id, trialable_type: "Organization")
      end

      test "does not clean up pending trials" do
        trial = create(:copilot_business_trial, :organization, state: :pending)
        organization = trial.trialable
        org_id = organization.id
        co = Copilot::Organization.new(organization)
        Copilot::Organization.new(organization).enable_copilot!
        Copilot::Organization.new(organization).disable_copilot!

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
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
        refute_includes logs, "Revoking copilot seat access for organization"
        refute Copilot::SeatAssignment.exists?(organization_id: org.id)
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org.id)
      end

      test "cleans up nothing if the org is billable" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        org = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(org)
        seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first)
        seat_assignment.convert_to_seats

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org.id, T.must(copilot_org.customer_for).id)
          end
        end

        refute_includes logs, "Revoking copilot seat access for organization"
        refute_empty Copilot::Seat.for_organization(org)
      end
    end

    context "with copilot_revokable_access enabled" do
      context "standalone org", skip_in_multitenant_mode: true do
        test "preserves and revokes existing seat assignments" do
          enable_feature_flag(:copilot_revokable_access)

          Copilot::ErrorReporter.expects(:report!).never
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).at_least_once
          Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).once

          organization = create(:organization, :zuora)
          co = Copilot::Organization.new(organization)
          org_id = organization.id

          team = create(:team, organization: organization)
          5.times do |_|
            user = create(:user)
            organization.add_member(user)
            team.add_member(user)
          end

          user_assignment = create(:copilot_seat_assignment, owner: organization, assignable: organization.admins.first, assigning_user: organization.admins.first)
          user_assignment.convert_to_seats

          assignment = create(:copilot_seat_assignment, assignable: team, owner: organization, assigning_user: organization.admins.first)
          assignment.convert_to_seats

          Copilot::Organization.new(organization).enable_copilot!
          Copilot::Organization.new(organization).disable_copilot!

          logs = capture_logs do
            assert_no_changes -> { Copilot::Seat.count } do
              ActiveRecord::Base.connected_to(role: :reading) do
                Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
              end
            end
          end

          user_seat_assignments = Copilot::SeatAssignment.where(assignable_type: "User", owner_id: org_id, owner_type: "Organization")
          revoked_team_assignment = Copilot::SeatAssignment.where(assignable_type: "Team", owner_id: org_id, owner_type: "Organization")

          assert_equal 1, user_seat_assignments.count
          assert user_seat_assignments.first&.pending_cancellation?
          assert user_seat_assignments.first&.access_revoked?
          assert_includes logs, "Revoking copilot seat access for organization"
          refute_empty revoked_team_assignment
          assert revoked_team_assignment.first&.pending_cancellation?
          assert revoked_team_assignment.first&.access_revoked?
          assert_equal 1, user_seat_assignments.count
          refute_empty Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org_id)
        end
      end

      context "enterprise-owned org" do
        test "revokes seaat assignments to the enterprise when the org has been removed" do
          enable_feature_flag(:copilot_revokable_access)

          Copilot::ErrorReporter.expects(:report!).never
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).at_least_once
          Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).once

          organization = create(:copilot_for_business_enabled_organization)
          ::Organization.any_instance.stubs(:deleted?).returns(true)
          co = Copilot::Organization.new(organization)
          org_id = organization.id

          team = create(:team, organization: organization)
          5.times do |_|
            user = create(:user)
            organization.add_member(user)
            team.add_member(user)
          end

          assignment = create(:copilot_seat_assignment, assignable: team, owner: organization, assigning_user: organization.admins.first)
          assignment.convert_to_seats

          logs = capture_logs do
            assert_no_changes -> { Copilot::Seat.count } do
              ActiveRecord::Base.connected_to(role: :reading) do
                Copilot::OrganizationCleaner.call(org_id, T.must(co.customer_for).id)
              end
            end
          end

          user_seat_assignments = Copilot::SeatAssignment.where(assignable_type: "User", owner_id: organization.business.id, owner_type: "Business")
          team_assignment = Copilot::SeatAssignment.where(assignable_type: "Team", owner_id: org_id, owner_type: "Organization")

          refute_empty Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org_id)
          assert_includes logs, "Revoking copilot seat access for organization"
          assert_equal 5, user_seat_assignments.count
          user_seat_assignments.each do |user_seat_assignment|
            assert user_seat_assignment&.pending_cancellation?
            assert user_seat_assignment&.access_revoked?
          end

          assert_empty team_assignment
        end
      end
    end

    test "logs expected cleaner state with copilot_org_cleaner_logging enabled" do
      enable_feature_flag(:copilot_revokable_access)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :zuora_invoiced_subscription })

      org = create(:copilot_for_business_enabled_organization, :with_azure_subscription)
      copilot_org = Copilot::Organization.new(org)
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first)
      seat_assignment.convert_to_seats

      Copilot::Business.new(org.business).disable_copilot!

      logs = capture_logs do
        assert_logged(
          "gh.copilot.org_cleaner.result": :revoke_to_org,
          "gh.copilot.org_cleaner.is_enterprise_owned": true,
          "gh.copilot.org_cleaner.has_revokable_access": true,
          "gh.copilot.org_cleaner.has_trial": false,
          "gh.copilot.org_cleaner.billable_owner_id": org.business.id,
          "gh.copilot.org_cleaner.billable_owner_type": "Business",
          "gh.copilot.org_cleaner.billable": true,
          "gh.copilot.org_cleaner.billable.result": "zuora_invoiced_subscription"
        ) do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::OrganizationCleaner.call(org.id, T.must(copilot_org.customer_for).id)
          end
        end
      end

      assert_includes logs, "Organization cleaner eligibility"

    end
  end
end if GitHub.copilot_enabled?
