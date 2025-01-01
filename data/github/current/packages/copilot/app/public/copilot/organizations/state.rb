# typed: strict
# frozen_string_literal: true

# User Permissions/Seat Assignment is a poor man's state machine.
#
# There are three states we can be in:
#
# 1. Disabled  - You can be brand new with no SeatAssignments OR you can have an Organization SeatAssignment pending cancellation with Seats
# 2. Allow All - Only an Organization SeatAssignment exists (no Users, Teams, or Invitation assignments exist) and it is not pending cancellation
# 3. Selected  - At least one non-Organization SeatAssignment exists not pending cancellation
#              - (any Organization SeatAssignment is pending cancellation)
#
# Both Disabled and Allow All expect to have a single Organization SeatAssignment pending cancellation or not, respectively
#
# The rub is that we have to figure out what to do with the SeatAssignment(s) as we transition between states.
#
# Note: we can only have one Organization SeatAssignment at a time and if we have an active Organization SeatAssignment,
#       we can't have any other SeatAssignments.
module Copilot
  module Organizations
    module State
      extend T::Helpers
      include Copilot::Helpers
      include Copilot::Organizations::Signatures

      abstract!

      include HasConfiguration

      delegate :seat_management_unconfigured?, :seat_management, to: :configuration

      # we could just call this on the organization object, but this is prettier
      sig { override.returns(ActiveSupport::TimeWithZone) }
      def pending_cancellation_date
        organization_object.next_metered_billing_cycle_starts_at
      end

      # ** Transitioning to Disabled:
      #
      # If we have existing Seats when we transition to Disabled, we will create an Organization SeatAssignment and
      # set it to pending cancellation. All existing Seats will be updated to point to the Organization SeatAssignment.
      #
      # If we don't have any existing Seats, we may have existing SeatAssignments that we have to remove (perhaps the conversion
      # to Seats hasn't happened yet)
      #
      #  Allow All -> Disabled
      #   - Organization SeatAssignment is updated to be pending cancellation
      #   - All Seats are already pointing at the Organization SeatAssignment
      #
      #  Selected Team/Users -> Disabled
      #   - User/Team/Invitation SeatAssignments are deleted
      #   - If Seats exist, Organization SeatAssignment is created and set to pending cancellation
      #   - All Seats are updated to point at the Organization SeatAssignment
      sig { override.params(assigning_user: T.nilable(::User)).void }
      def seat_management_disable!(assigning_user = nil)
        GitHub.logger.with_named_tags("code.function" => "seat_management_disable!", "code.namespace" => "Copilot::Organizations::State") do
          # let's see if we have an Organization Level SeatAssignment for this organization
          seat_assignment = find_organization_seat_assignment(assigning_user)

          with_write do
            seat_assignment.update_column(:pending_cancellation_date, pending_cancellation_date)

            GitHub.logger.info("Updating existing Seats to point to Org SeatAssignment")
            org_seats = Copilot::Seat.where(organization: organization_object)
            # Get seat assignments that are already pending cancellation. We won't be touching these.
            cancelled_seat_assignment_ids = Copilot::SeatAssignment.where(id: org_seats.pluck(:copilot_seat_assignment_id)).where.not(pending_cancellation_date: nil).pluck(:id)
            # Update all of those Seats to point at the Organization SeatAssignment
            update_count = org_seats.where.not(copilot_seat_assignment_id: cancelled_seat_assignment_ids).update_all(copilot_seat_assignment_id: seat_assignment.id)
            GitHub.logger.info("Updated existing Seats", "gh.copilot.state.update_count" => update_count)

            GitHub.logger.info("Disabling seat management settings", "gh.org.id" => organization_object.id)
            configuration.seat_management_disabled!

            instrument_seat_assignment_unassign(event: :seat_management_disabled, assigning_user_id: assigning_user&.id) do
              Copilot::SeatAssignment.where(organization: organization_object).where.not(assignable_type: "Organization").where.not(id: cancelled_seat_assignment_ids)
            end
          end
        end
      end

      # ** Transitioning to Allow All:
      #
      #  We need to end this transition with an Organization SeatAssignment that is not pending cancellation and Seats for all members pointing at it
      #
      #  Disabled -> Allow All
      #   - Organization SeatAssignment is created (if we are brand new) or restored (if we went from Allow All -> Disabled)
      #   - Seats are created for all users in the organization pointing to the Organization SeatAssignment
      #   - Any other SeatAssignments are deleted (if they exist)
      #
      #  Selected Team/Users -> Allow All
      #   - Organization SeatAssignment created/restored (if we previously went through Allow All/Selected then Disabled, we might have one pending cancellation)
      #   - Seats are created for all users in the organization pointing to the Organization SeatAssignment
      #   - Any other SeatAssignments are deleted (if they exist)
      sig { override.params(assigning_user: T.nilable(::User)).void }
      def seat_management_allow_all!(assigning_user = nil)
        return if seat_management_enabled_for_all?

        GitHub.logger.with_named_tags("code.function" => "seat_management_allow_all!", "code.namespace" => "Copilot::Organizations::State") do
          # Let's see if we have an Organization Level SeatAssignment for this organization
          # This will occur when we go from Disabled -> Allow All
          seat_assignment = find_organization_seat_assignment(assigning_user)

          with_write do
            # Update the Organization SeatAssignment to not be pending cancellation
            seat_assignment.update_column(:pending_cancellation_date, nil)

            # update existing seats to point to the Organization SeatAssignment
            GitHub.logger.info("Updating existing Seats to point to Org SeatAssignment")
            # Update all of those Seats to point at the Organization SeatAssignment
            update_count = Copilot::Seat.where(organization: organization_object).update_all(copilot_seat_assignment_id: seat_assignment.id)
            GitHub.logger.info("Updated existing Seats", "gh.copilot.state.update_count" => update_count)

            instrument_seat_assignment_unassign(event: :seat_management_allow_all, assigning_user_id: assigning_user&.id) do
              Copilot::SeatAssignment.where(organization: organization_object).where.not(assignable_type: "Organization")
            end

            GitHub.logger.info("Creating Seats for all users")
            # create seats for all users in the organization
            seat_assignment.delayed_converter_job unless seat_assignment.new_record?

            configuration.seat_management_enabled_for_all!
          end
        end
      end

      # ** Transitioning to Selected Team/Users:
      #
      # This is the most "exciting" transition.
      # We may have an Organization SeatAssignment. Or not.
      # The Organization SeatAssignmet could be pending cancellation. Or not.
      # The Organization SeatAssignment could have Seats for every Organization Member (or just some if we went Selected -> Disabled -> Selected) referencing it.  Or not.
      # We may have User/Team/Invitation SeatAssignments. Or not.
      # Those User/Team/Invitation SeatAssignments could be pending cancellation. Or not.
      # Those User/Team/Invitation SeatAssignments could have Seats referencing them. Or not.
      #
      # Also, the admin is given the option to keep all of the existing SeatAssignments (from Allow All) or start fresh.
      #
      #  Disabled -> Selected Team/Users
      #   - Disabled means that they either have never done Seat Management or they went from Allow All/Selected -> Disabled
      #   - If they are brand new, we don't really do much because they shouldn't have any existing Seats.
      #   - If we previously went through Allow All/Selected -> Disabled, we might have an Organization SeatAssignment pending cancellation
      #     with Seats pointing at it which we want to maintain until the end of the billing month
      #   - When the admin adds Team or User SeatAssignments, converting those to Seats will reuse Seats pointing at Organization SeatAssignment
      #   - If the Organization SeatAssignment has no more Seats related to it after creating new SeatAssignments, it will be deleted
      #
      #  Allow All -> Selected Team/Users (Start From Scratch)
      #   - Organization SeatAssignment is updated to be pending cancellation
      #   - Seats are already pointing at the Organization SeatAssignment
      #   - We need to maintain these Seats until the end of the billing month
      #   - When the admin adds Team or User SeatAssignments, converting those to Seats will reuse Seats pointing at Organization SeatAssignment
      #   - If the Organization SeatAssignment has no more Seats related to it after creating new SeatAssignments, it will be deleted
      #
      #  Allow All -> Selected Team/Users (Keep Seats)
      #   - Organization SeatAssignment is destroyed
      #   - User SeatAssignments are created for all members of the organization
      #   - Seats are refreshed to point at the User SeatAssignments
      #   - Removing a User SeatAssignment updates the pending cancellation on the SeatAssignment
      #   - Adding a Team SeatAssignment is really ineffective after this since User SeatAssignments are the most specific
      sig { override.params(keep_assignments: T::Boolean).void }
      def seat_management_selected_teams_and_users!(keep_assignments: false)
        GitHub.logger.with_named_tags(
          "code.function" => "seat_management_selected_teams_and_users!",
          "code.namespace" => "Copilot::Organizations::State",
          "gh.copilot.org.state.keep_assignments" => keep_assignments,
          "gh.copilot.org.state.setting" => seat_management,
          "gh.org.id" => organization_object.id,
        ) do
          GitHub.logger.info("Checking setting")
          return if seat_management_enabled_for_selected? # i mean, we are already there

          if organization_seat_assignment.present?
            # we have an organization SeatAssignment. This is cool - it means they have done some SeatManaging before.
            org_seat_assignment = T.must(organization_seat_assignment)

            GitHub.logger.info(
              "We have an organization seat assignment",
              "gh.copilot.seat_assignment.id" => org_seat_assignment.id,
            )

            with_write do
              GitHub.logger.info("Setting organization seat assignment to pending cancellation")
              org_seat_assignment.update_column(:pending_cancellation_date, pending_cancellation_date)
            end

            if keep_assignments
              GitHub.logger.info("We're keeping assignments")
              convert_organization_seat_assignment(T.must(organization_seat_assignment), keep_assignments, seat_management_disabled?, :seat_management_selected)
            else
              GitHub.logger.info("We are starting from scratch")
              with_write do
                # we aren't keeping the assignments, so we need to see if we have any seats for existing seat assignments.
                # Then, we need to update all of the Seats to point at the Organization SeatAssignment
                Copilot::Seat.where(organization: organization_object).update_all(copilot_seat_assignment_id: org_seat_assignment.id)

                # we need to delete any other SeatAssignments (we shouldn't get to this because we are coming from a state where there are no other SeatAssignments but just in case)
                instrument_seat_assignment_unassign(event: :seat_management_selected, assigning_user_id: nil) do
                  Copilot::SeatAssignment.where(organization: organization_object).where.not(id: [org_seat_assignment.id])
                end
              end
            end
          else
            GitHub.logger.info("No organization seat assignment found")
            # they are probably brand new which means they won't have any Seats
            # If we don't have any existing Seats, this is a no-op.
            unless Copilot::Seat.exists?(organization_id: organization_object.id)
              configuration.seat_management_enabled_for_selected!
              return
            end

            # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
            # 🚨🚨🚨 What did you do? You shouldn't be here.  🚨🚨🚨
            # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
            #
            # So, you have a Seat but no Organization SeatAssignment to reference it.
            # But you came from Disabled or Allow All - which both remove non-Organization SeatAssignments so this is pretty weird
            # Maybe you forgot to clean up a Seat when you cleaned up the SeatAssignment, or you hit some race condition with multiple
            # admins updating CfB seat assignments at the same time?
            #
            # We'll handle it and make sure everything is okay, but you really should question any life choices that got you here.
            # We handle these unmanaged seats by assigning them to a new Organization SeatAssignment that's set to be cancelled
            # at the end of the month. We would just delete them, but we need to make sure we bill for them properly.

            # we're gonna log/failbot this so we need to iterate quickly over them
            seat_details            = Copilot::Seat.for_organization(organization_object).pluck(:id, :copilot_seat_assignment_id)
            seat_assignment_details = Copilot::SeatAssignment.for_organization(organization_object).pluck(:id, :assignable_type, :assignable_id, :assigning_user_id)

            GitHub.logger.info(
              "Found unmanaged seats for organization",
              "gh.copilot.state.seat_details" => seat_details,
              "gh.copilot.state.seat_assignment_details" => seat_assignment_details,
            )
            with_write do
              GitHub.logger.info("Creating new Organization SeatAssignment with pending_cancellation_date set")
              new_org_seat_assignment = find_organization_seat_assignment
              new_org_seat_assignment.update_column(:pending_cancellation_date, pending_cancellation_date)

              GitHub.logger.info("Updating Organization Seats to point to Organization SeatAssignment")
              Copilot::Seat.for_organization(organization_object).update_all(copilot_seat_assignment_id: new_org_seat_assignment.id)

              instrument_seat_assignment_unassign(event: :seat_management_selected) do
                Copilot::SeatAssignment.where(organization: organization_object).where.not(id: [new_org_seat_assignment.id])
              end
            end
          end

          with_write do
            configuration.seat_management_enabled_for_selected!
          end
        end
      end

      sig { override.returns(T::Boolean) }
      def seat_management_disabled?
        configuration.seat_management_disabled? || configuration.seat_management_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def seat_management_enabled_for_all?
        configuration.seat_management_enabled_for_all?
      end

      sig { override.returns(T::Boolean) }
      def seat_management_enabled_for_selected?
        configuration.seat_management_enabled_for_selected?
      end

      sig { override.returns(T.nilable(Copilot::SeatAssignment)) }
      def organization_seat_assignment
        Copilot::SeatAssignment.where(
          organization: organization_object,
          assignable_id: organization_object.id,
          assignable_type: "Organization"
        ).first
      end

      sig { override.returns(String) }
      def seat_management_setting
        return "disabled" if configuration.seat_management_unconfigured?

        configuration.seat_management
      end

      sig { returns(String) }
      def friendly_seat_management_setting
        return "Unconfigured" if configuration.seat_management_unconfigured?
        return "Disabled" if configuration.seat_management_disabled?
        return "Enabled for All" if configuration.seat_management_enabled_for_all?
        return "Enabled for Selected Users/Teams" if configuration.seat_management_enabled_for_selected?
        "Unknown"
      end

      sig { params(org_slug: String, team_slug: T.nilable(String)).returns(Copilot::SeatAssignment) }
      def create_enterprise_team(org_slug:, team_slug: nil)
        enterprise_team = EnterpriseTeam.create(
          business: copilot_business&.business_object,
          name: [org_slug, team_slug, EnterpriseTeam::COPILOT_TEAM_SUFFIX].compact.join("-")
        )
        team_assignment = enterprise_team.enterprise_team_assignments.build(assignment_type: "copilot")
        team_assignment.skip_event_emissions = true
        team_assignment.save!

        Copilot::SeatAssignment.create_for_enterprise_team!(enterprise_team)
      end

      sig do
        params(
          new_seat_assignment: Copilot::SeatAssignment,
          old_seat_assignments: T::Array[Copilot::SeatAssignment],
          members: T::Array[User]
        ).void
      end
      def reassign_members_to_enterprise_team(new_seat_assignment:, old_seat_assignments:, members:)
        unless members.empty?
          if old_seat_assignments.length == 1 && old_seat_assignments.first&.assignable_type == "Team"
            reassign_org_team_to_enterprise_team(old_seat_assignment: T.must(old_seat_assignments.first), new_seat_assignment: new_seat_assignment, members: members)
          else
            enterprise_team = new_seat_assignment.assignable
            enterprise_team.bulk_add_members(users: members)
          end

          # First get the existing seats we're moving
          Copilot::Seat.where(copilot_seat_assignment_id: old_seat_assignments.map(&:id)).in_batches do |seats|
            # Existing seats now point to the new ET seat assignment
            seats.update_all(
              copilot_seat_assignment_id: new_seat_assignment.id,
              organization_id: nil,
              updated_at: Date.current
            )
          end
        end
      end

      sig do
        params(
          old_seat_assignment: Copilot::SeatAssignment,
          new_seat_assignment: Copilot::SeatAssignment,
          members: T::Array[User]
        ).void
      end
      def reassign_org_team_to_enterprise_team(old_seat_assignment:, new_seat_assignment:, members:)
        enterprise_team = new_seat_assignment.assignable
        old_team = Team.find(old_seat_assignment.assignable_id)
        old_team_external_group_id = old_team.external_group_team&.external_group_id
        if old_team_external_group_id.present?
          enterprise_team_group_mapping = EnterpriseTeamGroupMapping.new
          enterprise_team_group_mapping.enterprise_team = enterprise_team
          enterprise_team_group_mapping.external_group_id = old_team_external_group_id
          enterprise_team_group_mapping.save!
        else
          enterprise_team.bulk_add_members(users: members)
        end
      end

      sig { returns(T::Boolean) }
      def migrate_to_enterprise_teams
        # Business needs to be a beta participant + not have any IdP managed EnterpriseTeam
        return false unless copilot_business&.eligible_to_migrate_to_enterprise_teams?

        # No configuration to migrate.
        return false if configuration.seat_management_unconfigured?

        # Copilot currently disabled. In this state, there can be an Organization SeatAssignment that is pending cancellation.
        return false if configuration.seat_management_disabled?

        individual_access_members = T.let([], T::Array[User])
        individual_access_members_old_seat_assignments = T.let([], T::Array[Copilot::SeatAssignment])

        if configuration.seat_management_enabled_for_all? || configuration.seat_management_enabled_for_selected?
          Copilot::SeatAssignment.includes(:assignable).where(organization: organization_object).find_each do |seat_assignment|
            case seat_assignment.symbolized_assignable_type
            when :ORGANIZATION
              # Seat management is currently configured to provide copilot access for all current and future users.
              # We cannot auto add all future enterprise users to the EnterpriseTeam with direct memberships but we can
              # still add all current members to a new team.
              individual_access_members += organization_object.members
              individual_access_members_old_seat_assignments << seat_assignment
            when :USER
              individual_access_members << seat_assignment.assignable
              individual_access_members_old_seat_assignments << seat_assignment
            when :TEAM
              new_team = create_enterprise_team(org_slug: organization_object.login, team_slug: seat_assignment.assignable.slug)
              reassign_members_to_enterprise_team(
                new_seat_assignment: new_team,
                old_seat_assignments: [seat_assignment],
                members: seat_assignment.assignable.members.to_a
              )
            else
              # Ignore OrganizationInvites because basic emus don't use invitations.
            end
          end
        end

        unless individual_access_members.empty?
          individual_access_enterprise_team ||= create_enterprise_team(org_slug: organization_object.login)
          reassign_members_to_enterprise_team(
            new_seat_assignment: individual_access_enterprise_team,
            old_seat_assignments: individual_access_members_old_seat_assignments,
            members: individual_access_members
          )
        end

        # Clean up the old seat assignments
        instrument_seat_assignment_unassign(event: :enterprise_teams_migration) do
          Copilot::SeatAssignment.where(organization: organization_object)
        end

        # Create the config for the standalone business (if it doesn't exist).
        # The org config will get cleaned up when the org is destroyed, and shouldn't have bearing on the actual
        # seats anyway (@veverkap)
        T.must(copilot_business).enable_copilot!

        true
      end

      private

      sig { params(assigning_user: T.nilable(::User)).returns(Copilot::SeatAssignment) }
      def find_organization_seat_assignment(assigning_user = nil)
        GitHub.logger.with_named_tags("code.function" => "find_organization_seat_assignment", "code.namespace" => "Copilot::Organizations::State") do
          # let's see if we have an Organization Level SeatAssignment for this organization
          if organization_seat_assignment.present?
            GitHub.logger.info(
              "Existing Organization SeatAssignment Found",
              "gh.copilot.seat_assignment.id" => T.must(organization_seat_assignment).id,
              )

            T.must(organization_seat_assignment).make_sure_owner_is_populated!
            T.must(organization_seat_assignment)
          else
            with_write do
              GitHub.logger.info("Creating Organization SeatAssignment")
              Copilot::SeatAssignment.create!(
                owner_type: "Organization",
                owner_id: organization_object.id,
                organization: organization_object,
                assignable_type: "Organization",
                assignable_id: organization_object.id,
                # Assigning user is mostly for the sake of instrumentation.  We want this method to be called
                # with the actor who toggled the seat management setting passed through so that the eventual
                # seat_added events that result from this org seat assignment are attributed to that user.
                assigning_user: assigning_user || organization_object.admins.first
              )
            end
          end
        end
      end

      # to get here, we need to have an Organization Seat Assignment - that means we come from Allow All or Disabled
      #
      # the org admin can choose to keep the existing assignments or start from scratch
      #
      # if they are coming from allow all and are keeping their existing seat assignment (the entire organization), we need
      # to make sure to create a User Seat Assignment for each member of the organization
      #
      # if they are coming from disabled and are keeping their existing seat assignments (selected user or entire organization),
      # we need to make sure to create a User Seat Assignment for each Seat that exists currently
      sig { params(organization_seat_assignment: Copilot::SeatAssignment, keep_assignments: T::Boolean, disabled: T::Boolean, event: Symbol).void }
      def convert_organization_seat_assignment(organization_seat_assignment, keep_assignments, disabled, event)
        GitHub.logger.with_named_tags(
          "code.function" => "convert_organization_seat_assignment!",
          "code.namespace" => "Copilot::Organizations::State",
          "gh.copilot.org.state.keep_assignments" => keep_assignments,
          "gh.copilot.org.state.disabled" => disabled,
          "gh.copilot.seat_assignment.id" => organization_seat_assignment.id,
          "gh.org.id" => organization_object.id,
        ) do
          # so, we need to find out if we're create User Seat Assignments for all members or just for the seats existing
          enumerable = disabled ? Copilot::Seat.for_organization(organization_object).map(&:assigned_user_id) : organization_object.member_ids

          GitHub.logger.info(
            "Loaded enumerable for Seat Assignments",
            "gh.copilot.org.state.seat_assignment_inserts.count" => enumerable.count,
          )

          # it's faster if we delete all of the seats for them and start over
          GitHub.logger.info("Deleting all existing seats")
          with_write do
            ApplicationRecord::Domain::Copilot.connection.delete(Arel.sql(<<-SQL, organization_id: organization_object.id))
              DELETE FROM copilot_seats WHERE organization_id = :organization_id
            SQL
          end

          new_pending_cancellation = keep_assignments ? nil : organization_seat_assignment.pending_cancellation_date

          # let's take that enumerable and make some inserts
          seat_assignment_inserts = load_seat_assignment_inserts(enumerable, organization_seat_assignment.assigning_user_id, new_pending_cancellation)

          with_write do
            # let's delete the organization seat assignment
            instrument_seat_assignment_unassign(event: event) do
              Copilot::SeatAssignment.where(id: organization_seat_assignment.id, organization: organization_object)
            end

            if seat_assignment_inserts.any?
              GitHub.logger.info("Inserting User Seat Assignments In Batches Of 1000")
              seat_assignment_inserts.in_groups_of(1000, false) do |batch_scope|
                Copilot::SeatAssignment.throttle do
                  Copilot::SeatAssignment.insert_all(batch_scope).inspect
                end
                GitHub.logger.info("Inserted batch", "gh.copilot.org.state.seat_assignments_inserted.count" => batch_scope.count)
              end
            end

            GitHub.logger.info("Loading inserted seat assignments")
            # we need to get the seat_assignments we just inserted, so we're gonna
            results = ApplicationRecord::Domain::Copilot.connection.select_rows(Arel.sql(<<-SQL, organization_id: organization_object.id))
              SELECT id, assignable_id, organization_id FROM copilot_seat_assignments WHERE organization_id = :organization_id
            SQL

            # we will either insert completely new seats or update the seats to point to the new seat assignments
            seat_inserts = results.to_a.to_a.map do |seat_assignment_id, assignable_id, organization_id|
              {
                copilot_seat_assignment_id: seat_assignment_id,
                assigned_user_id: assignable_id,
                organization_id: organization_id,
              }
            end

            if seat_inserts.any?
              GitHub.logger.info("Updating seats to point to new seat assignments")
              seat_inserts.in_groups_of(1000, false) do |batch_scope|
                Copilot::Seat.throttle do
                  Copilot::Seat.insert_all(batch_scope)
                end
                GitHub.logger.info("Inserted batch", "gh.copilot.org.state.seats_inserted.count" => batch_scope.count)
              end
            end
          end
        end
      end

      sig do
        params(
          enumerable: T::Array[Integer],
          assigning_user_id: Integer,
          pending_cancellation_date: T.nilable(Date),
        ).returns(T::Array[{ organization_id: T.nilable(Integer), owner_id: T.nilable(Integer), owner_type: String, assignable_type: String, assignable_id: Integer, assigning_user_id: Integer, pending_cancellation_date: T.nilable(Date) }])
      end
      def load_seat_assignment_inserts(enumerable, assigning_user_id, pending_cancellation_date)
        GitHub.logger.with_named_tags(
          "code.function" => "load_seat_assignment_inserts!",
          "code.namespace" => "Copilot::Organizations::State",
          "gh.copilot.seat_assignment_inserts.count" => enumerable.count,
          "gh.copilot.seat_assignment_inserts.assigning_user_id" => assigning_user_id,
        ) do
          GitHub.logger.info("Mapping enumerable")
          # let's create new seat assignments for all of the users
          enumerable.map do |assigned_user_id|
            {
              organization_id: organization_object.id,
              owner_id: organization_object.id,
              owner_type: "Organization",
              assignable_type: "User",
              assignable_id: assigned_user_id,
              assigning_user_id: assigning_user_id,
              pending_cancellation_date: pending_cancellation_date
            }
          end
        end
      end

      sig { params(event: Symbol, assigning_user_id: T.nilable(Integer),  block: T.proc.returns(ActiveRecord::Relation)).void }
      def instrument_seat_assignment_unassign(event:, assigning_user_id: nil,  &block)
        # If we have any User/Team/Invitation SeatAssignments, delete them because the Seats aren't pointing at them anymore
        GitHub.logger.info("Deleting any other SeatAssignments")

        assignments_to_delete = block.call
        assignments_to_delete.destroy_all
      end
    end
  end
end
