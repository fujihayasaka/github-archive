# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class Assigner
      extend T::Helpers
      include Kernel
      include Copilot::Errors

      sig { returns(Copilot::Owner) }
      attr_reader :owner

      sig { params(owner: Copilot::Owner).void }
      def initialize(owner)
        @owner = owner
      end

      sig { params(assignable: Copilot::Assignable, assigning_user: ::User).returns(GitHub::Result) }
      def assign(assignable, assigning_user)
        GitHub::Result.new do
          unless user_can_assign?(assigning_user)
            raise SeatAssignmentError, "Inviting User is not an admin of the #{owner.class.name}"
          end

          if assigned?(assignable)
            # assigned? will return false for enterprise teams so this is okay to cast
            refresh_assignable(T.cast(assignable, Copilot::OrganizationAssignable), assigning_user)
          else
            case assignable
            when ::Organization
              assignment = handle_organization_assignable(assignable, assigning_user)
              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(assignment, assigning_user, :direct_assignment)
              assignment
            when ::User
              assignment = handle_user_assignable(assignable, assigning_user)
              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(assignment, assigning_user, :direct_assignment)
              assignment
            when ::BusinessTeam
              assignment = handle_business_team_assignable(assignable, assigning_user)
              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(assignment, assigning_user, :direct_assignment)
              assignment
            when ::Team
              assignment = handle_team_assignable(assignable, assigning_user)
              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(assignment, assigning_user, :direct_assignment)
              assignment
            when ::OrganizationInvitation
              # we don't instrument this here because organization invitations actually come through this twice
              handle_org_invitation_assignable(assignable, assigning_user)
            when ::EnterpriseTeam
              # we don't instrument this because these are instrumented on create
              EnterpriseTeamAssignment.find_or_create_by!(enterprise_team: assignable, assignment_type: :copilot)
            end
          end
        end
      end

      sig { params(assignable: Copilot::Assignable, unassigning_user: ::User).returns(GitHub::Result) }
      def unassign(assignable, unassigning_user)
        GitHub::Result.new do
          if assignable.is_a?(::EnterpriseTeam)
            ent_team_assignment = EnterpriseTeamAssignment.find_by(enterprise_team: assignable, assignment_type: :copilot)
            if ent_team_assignment.present?
              ent_team_assignment.destroy
            else
              raise SeatAssignmentError, "#{assignable.class} is not assigned to a seat"
            end
          else
            if assigned?(assignable)
              assignment = Copilot::SeatAssignment.find_by!(
                assignable_id: assignable.id,
                assignable_type: assignable_type(assignable),
                owner_id: owner.id,
                owner_type: owner.class.to_s,
              )

              # this will instrument unassignment
              # and destroy the seat assignment if the unassigning is happening within the cooldown period
              assignment.unassign!(unassigning_user)
            else
              raise SeatAssignmentError, "#{assignable.class} is not assigned to a seat"
            end
          end
        end
      end

      sig { params(email_address: String, assigning_user: ::User).returns(GitHub::Result) }
      def assign_email_address(email_address, assigning_user)
        GitHub::Result.new do
          Kernel.raise SeatAssignmentError.new("Businesses cannot invite users") if owner.is_a?(::Business)
          organization = T.cast(owner, ::Organization)

          # we're not allowed to let emu organizations invite users at all
          Kernel.raise Copilot::Errors::EMUInvitationError.new("EMUs must be added to the organization before they can be assigned seats") if organization.enterprise_managed_user_enabled?
          # let's see if this email address belongs to anyone
          user = UserEmail.find_by(email: email_address)&.user
          if user.present?
            result = assign(user, assigning_user)

            Kernel.raise result.error unless result.ok?
            result.value!
          else

            # okay, they don't have a verified email, so let's invite this person and assign them
            invitation = organization.invite(email: email_address, inviter: assigning_user, invitation_source: :member)
            result = assign(invitation, assigning_user)

            Kernel.raise result.error unless result.ok?

            assignment = result.value!
            Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(
              assignment,
              assigning_user,
              :direct_assignment_by_email,
            )
            assignment
          end
        end
      end

      sig { params(email_address: String, unassigning_user: ::User).returns(GitHub::Result) }
      def unassign_email_address(email_address, unassigning_user)
        GitHub::Result.new do
          Kernel.raise SeatAssignmentError.new("Businesses cannot invite users") if owner.is_a?(::Business)
          organization = T.cast(owner, ::Organization)
          # let's see if this email address belongs to anyone
          user = UserEmail.find_by(email: email_address)&.user
          if user.present?
            result = unassign(user, unassigning_user)

            Kernel.raise result.error unless result.ok?
            result.value!
          else
            # okay, they don't have a verified email, so let's invite this person and assign them
            invitation = ::OrganizationInvitation.find_by!(email: email_address, organization: organization)
            result = unassign(invitation, unassigning_user)

            Kernel.raise result.error unless result.ok?
            result.value!
          end
        end
      end

      private

      sig { params(assigning_user: ::User).returns(T::Boolean) }
      def user_can_assign?(assigning_user)
        return true if owner.adminable_by?(assigning_user)
        owner.is_a?(::Organization) && owner.resources.organization_copilot_seat_management.writable_by?(assigning_user)
      end

      sig { params(assignable: Copilot::Assignable).returns(T::Boolean) }
      def assigned?(assignable)
        return false if assignable.is_a?(::EnterpriseTeam)

        Copilot::SeatAssignment.where(
          assignable_id: assignable.id,
          assignable_type: assignable_type(assignable),
          owner_id: owner.id,
          owner_type: owner.class.to_s,
        ).exists?
      end

      sig { params(assignable: OrganizationAssignable, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def refresh_assignable(assignable, assigning_user)
        assignment = Copilot::SeatAssignment.find_by!(assignable_id: assignable.id,
                                                      assignable_type: assignable_type(assignable),
                                                      owner_id: owner.id,
                                                      owner_type: owner.class.to_s)

        # see if we're really refreshing it
        pending_cancellation_date = assignment.pending_cancellation_date

        assignment.pending_cancellation_date = nil
        assignment.assigning_user = assigning_user
        assignment.copy_organization_to_owner # TODO: Remove this once organization is removed from seat assignments
        assignment.save!

        if pending_cancellation_date.present?
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_refreshed(
            assignment,
            assigning_user,
            pending_cancellation_date_was: pending_cancellation_date.iso8601,
          )
        else
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_reused(
            assignment,
            assigning_user,
          )
        end

        assignment
      end

      sig { params(assignable: ::Organization, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def handle_organization_assignable(assignable, assigning_user)
        Kernel.raise SeatAssignmentError.new("Businesses cannot assign seats to orgs") if owner.is_a?(::Business)

        Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: owner.id,
          assignable_type: "Organization", #let's make sure this comes through
          assignable_id: assignable.id,
          assigning_user: assigning_user
        )
      end

      sig { params(user: ::User, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def handle_user_assignable(user, assigning_user)
        # Organization invitations don't check if the user has been suspended prior to creation
        # To avoid creating a seat assignment with an invitation pointing to a suspended user, lets bail here.
        # This check is somewhat redundant, as creating a seat assignment will already fail if the user is suspended AND and org member
        Kernel.raise SeatAssignmentError.new("Cannot create assignments for a suspended user") if user.suspended?

        if owner.is_a?(::Business)
          business = T.cast(owner, ::Business)
          unless business.can_assign_copilot_to_business_users?
            Kernel.raise SeatAssignmentError.new("Businesses cannot assign seats to users")
          end
          Kernel.raise SeatAssignmentError, "User is not a member of the business" unless business.unaffiliated_member?(user)

          Copilot::SeatAssignment.create!(
            owner_type: "Business",
            owner_id: owner.id,
            organization: nil,
            assignable: user,
            assigning_user: assigning_user
          )
        else
          organization = T.cast(owner, ::Organization)

          copilot_user = Copilot::User.new(user)
          business_trial = Copilot::Organization.new(organization).business_trial
          organization_member = organization.member_ids.include?(user.id)

          if business_trial.present? && business_trial.active?
            # this organization is on a business trial and it's active, so we gotta check some stuff first
            # first - is this user an organization member?
            Kernel.raise SeatAssignmentError, "User is not a member of the organization" unless organization_member

            # okay, they are an organization member - let's see if they are a CFI user
            auth = copilot_user.copilot_authorizer_object_no_snippy
            if auth.access_allowed? && copilot_user.has_cfi_access? && !auth.has_limited_access?
              Kernel.raise SeatAssignmentError, "User already has Copilot access and cannot be assigned to a seat during a trial"
            end
          end

          if organization_member
            # we already know about how awesome they are!
            Copilot::SeatAssignment.create!(
              owner_type: "Organization",
              owner_id: organization.id,
              organization: organization, # TODO: Remove this once organization is removed from seat assignments
              assignable: user,
              assigning_user: assigning_user
            )
          else
            Kernel.raise Copilot::Errors::EMUInvitationError.new("EMUs must be added to the organization before they can be assigned seats") if organization.enterprise_managed_user_enabled?

            # we gotta see if they want to join our awesomeness
            invitation = organization.invite(user, inviter: assigning_user, invitation_source: :member)
            result = assign(invitation, assigning_user)

            Kernel.raise result.error unless result.ok?

            result.value!
          end
        end
      end

      sig { params(business_team: ::BusinessTeam, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def handle_business_team_assignable(business_team, assigning_user)
        Kernel.raise SeatAssignmentError.new("Only businesses can assign seats to business teams") unless owner.is_a?(::Business)

        Copilot::SeatAssignment.create_for_business_team!(business_team, assigning_user)
      end

      sig { params(team: ::Team, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def handle_team_assignable(team, assigning_user)
        Kernel.raise SeatAssignmentError.new("Businesses cannot assign seats to teams") if owner.is_a?(::Business)

        Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: owner.id,
          organization: owner, # TODO: Remove this once organization is removed from seat assignments
          assignable: team,
          assigning_user: assigning_user
        )
      end

      sig { params(organization_invitation: ::OrganizationInvitation, assigning_user: ::User).returns(Copilot::SeatAssignment) }
      def handle_org_invitation_assignable(organization_invitation, assigning_user)
        Kernel.raise SeatAssignmentError.new("Businesses cannot assign seats to organization invitations") if owner.is_a?(::Business)

        Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: owner.id,
          organization: owner, # TODO: Remove this once organization is removed from seat assignments
          assignable: organization_invitation,
          assigning_user: assigning_user
        )
      end

      sig { params(assignable: OrganizationAssignable).returns(String) }
      def assignable_type(assignable)
        assignable_type = assignable.class.name.to_s
        assignable_type = "Organization" if assignable_type == "::Organization"
        assignable_type
      end
    end
  end
end
