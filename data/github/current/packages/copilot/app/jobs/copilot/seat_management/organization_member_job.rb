# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # We have three different events that we can receive.
    #
    # :add_member and :restore_member are handled the same way - we check if the organization has an
    # org-wide assignment, and if so, we create a seat for the user.
    # :remove_member is handled by the OrganizationRemoveMemberJob, but can be received by this one. In that case,
    # we forward the call to the OrganizationRemoveMemberJob.
    class OrganizationMemberJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job
      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:organization_id])&.business
      end

      VALID_ACTIONS = T.let(%i[
        add_member
        restore_member
      ].freeze, T::Array[Symbol])

      sig do
        params(
          user_id: Integer,
          organization_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
          invitation_email: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(user_id:, organization_id:, action: :unknown, transaction_id: nil, invitation_email: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.actor.id" => actor_id,
          "gh.copilot.job_action" => action,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.org.id" => organization_id,
          "gh.org.invitation.email" => invitation_email,
          "gh.user.id" => user_id,
        ) do
          @user_id         = T.let(user_id, T.nilable(Integer))
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))
          @invitation_email = T.let(invitation_email, T.nilable(String))
          @actor = T.let(::User.find_by(id: @actor_id), T.nilable(::User))

          # We pulled the :remove_member action out of this and made a separate job for it.
          # if we get that action here in transition to the new job, we should call that job
          if action == :remove_member
            GitHub.dogstats.increment "copilot.organization_member_job.remove_member"
            Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_later(
              user_id: user_id,
              organization_id: organization_id,
              transaction_id: transaction_id,
              payload: payload,
            )
            return
          end
          raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

          # load up the organization - this is required so if it isn't there, report an exception. We might want to tweak this later
          organization = ::Organization.find_by(id: organization_id)
          return report_error("Invalid Organization") unless organization

          copilot_org = Copilot::Organization.new(organization)
          unless copilot_org.copilot_for_business_enabled?
            GitHub.logger.info("User being added to org that doesn't have Copilot enabled, exiting")
            return
          end

          user = ::User.find_by(id: user_id)
          unless user
            # why?  just why?  what is happening?  we don't have a user but the user was added to the org or restored or something?
            GitHub.logger.error("Invalid User")
            Copilot::SeatManagement::UserJob.perform_now(user_id: user_id, clean_records: true)
            return
          end

          if user.suspended?
            report_error("User is suspended but is being added to an organization which has a SeatAssignment, exiting.")
            return
          end

          # When an org member is removed from an organization that is set to allow all members, we create a new seat assignment
          # for that member, and set a pending cancellation date.
          #
          # If the member is added back to the organization, we want to ensure their Copilot access is reinstated.
          # We don't want to reinstate the cancelled assignment if:
          # * the organization has seat management set to allow all.
          # * the user has a seat through a team assignment.
          # * the user is suspended
          #
          # Otherwise, we will reinstate the existing cancelled assignment.
          existing_cancelled_user_assignment = Copilot::SeatAssignment.where(
            organization_id: @organization_id,
            assignable_type: "User",
            assignable_id: @user_id
          ).and(Copilot::SeatAssignment.where.not(pending_cancellation_date: nil)).first
          org_seat_assignment = Copilot::SeatAssignment
            .for_organization(organization)
            .where(
              assignable_type: "Organization",
              assignable_id: @organization_id,
            )
            .where(pending_cancellation_date: nil)
            .first

          if existing_cancelled_user_assignment.present?
            if copilot_org.seat_management_enabled_for_all?

              if org_seat_assignment.nil?
                GitHub.logger.info(
                  "No org seat assignment found, but seat management is set to allow all",
                  "gh.org.id" => organization.id,
                )
                handle_copilot_error(Copilot::Errors::SeatAssignmentError.new("Missing org seat assignment for allow all setting"))
                return
              end

              GitHub.logger.info(
                "User reinstated to organization with allow all setting, destroying old SeatAssignment and repointing seats.",
                seat_assignment_log_details(existing_cancelled_user_assignment)
              )

              with_write do
                existing_cancelled_user_assignment.seats.each do |seat|
                  # There should only be one seat, but we loop through just in case.
                  # The deduplicate job will remove any duplicates.
                  GitHub.logger.info("Updating seat assignment for seat",
                    "gh.copilot.seat.id" => seat.id,
                    "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
                    "gh.copilot.seat.old_seat_assignment_id" => seat.copilot_seat_assignment_id,
                    "gh.copilot.seat.new_seat_assignment.id" => org_seat_assignment.id,
                  )
                  seat.update_column(:copilot_seat_assignment_id, org_seat_assignment.id)
                end
                # logging reinstatement with the existing cancelled assignment so that the event has the user's metadata
                existing_cancelled_user_assignment.log_reinstatement_and_refund_user(:user_restored_to_org)
                existing_cancelled_user_assignment.destroy
              end
            else
              # Seat management is set to something other than "allow all", try to reinstate access.
              # First check if a team assignment exists. Even if a seat doesn't exist at this moment, the user
              # has access through the team assignment, and a seat will be created when the TeamSyncJob runs.
              team_assignment = Copilot::SeatAssignment.where(
                owner_id: organization.id,
                owner_type: "Organization",
                assignable_type: "Team",
                assignable_id: user.team_ids,
                access_revoked_at: nil,
              ).first

              if team_assignment.nil? && copilot_org.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                GitHub.logger.info("Reinstating existing User SeatAssignment")
                with_write do
                  existing_cancelled_user_assignment.reinstate_access!(:user_restored_to_org, options: { uncancel: !copilot_org.seat_management_disabled? })
                  # Try to convert a seat just in case the seat assignment didn't have a seat; perhaps the assignment
                  # was created and the user was removed from the org before the seat was created.
                  existing_cancelled_user_assignment.convert_to_seats
                end

                return
              elsif team_assignment.present?
                GitHub.logger.info("User has team assignment, repointing seats.")

                with_write do
                  existing_cancelled_user_assignment.seats.each do |seat|
                    GitHub.logger.info("Updating seat assignment for seat",
                      "gh.copilot.seat.id" => seat.id,
                      "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
                      "gh.copilot.seat.old_seat_assignment_id" => seat.copilot_seat_assignment_id,
                      "gh.copilot.seat.new_seat_assignment.id" => team_assignment.id,
                    )
                    seat.update_column(:copilot_seat_assignment_id, team_assignment.id)
                  end
                  existing_cancelled_user_assignment.log_reinstatement_and_refund_user(:user_restored_to_org)
                  existing_cancelled_user_assignment.destroy
                end
              end
            end
          end

          # if a Seat already exists, we don't need to do anything because this is an additive change
          if Copilot::Seat.where(organization_id: @organization_id, assigned_user_id: @user_id).exists?
            GitHub.logger.info("Existing Seat found for User")
            GitHub.dogstats.increment "copilot.organization_member_job.member_changed.exists"
            return
          end

          GitHub.logger.info("No existing seat found for User")

          if org_seat_assignment.present?
            unless copilot_org.seat_management_enabled_for_all?
              # An org assignment that is not pending cancellation and not set to allow all members is an error.
              handle_copilot_error(
                Copilot::Errors::SeatCreationError.new("Org-level assignment, but seat management is not enabled for all"),
                seat_assignment_log_details(org_seat_assignment).merge({
                  "gh.org.id" => organization.id,
                  "gh.user.id" => user.id,
                })
              )
              return
            end

            GitHub.logger.info("Organization SeatAssignment found, creating Seat for newly-added member",
                               "gh.copilot.seat_assignment.id" => org_seat_assignment.id)

            org_seat_assignment.make_sure_owner_is_populated! # this is wrapped in a write

            # we have an ACTIVE organization seat assignment, which means the
            # admin wants to have any new members automatically granted a
            # seat, so we need to create a seat for this user since they
            # didn't have one already
            seat = with_write do
              # this will trigger a callback that creates a SeatHistory record
              Copilot::Seat.create!(
                seat_assignment: org_seat_assignment,
                organization: organization,
                assigned_user: user,
              )
            rescue ActiveRecord::RecordInvalid
              # so, this means that the user isn't a member of the organization? how did we get here?
              GitHub.logger.info(
                "User is not a member of the organization",
                "gh.copilot.seat_assignment.id" => org_seat_assignment.id,
                "gh.org.id" => organization.id,
                "gh.user.id" => user.id,
                "gh.user.organizations_includes_organization" => user.organizations.include?(organization),
                "gh.organization.member_ids_includes_user" => organization.member_ids.include?(user.id),
                "gh.user.organization.ids" => user.organizations.map(&:id),
                "gh.copilot.job_payload" => @payload,
              )
              return
            end

            GitHub.logger.info("Seat created for newly-added organization member",
                               "gh.copilot.seat.id" => seat.id,
                               "gh.copilot.seat_assignment.id" => org_seat_assignment.id)

            # instrument that baby
            Copilot::Instrumenter.instrument_copilot_for_business_seat_added(
              organization,
              seat.assigned_user_id,
              @actor,
              :member_added_organization
            )

            Copilot::SeatManagement::SeatAssignedJob.perform_later(
              seat.organization_id,
              seat.assigned_user_id,
              seat: seat,
            )
            GitHub.dogstats.increment "copilot.organization_member_job.member_changed.all_org"
            return
          else
            GitHub.logger.info("No Organization SeatAssignment found")

            # in this case, there is no Organization level SeatAssignment, so we want to see if the organization admin
            # has said that they want to give a Seat to this user - that really only happens in this codepath if they have
            # an OrganizationInvitation.  If they don't have an invitation, then we don't need to do anything
            #
            # If the user was also added to a Team, then a different job handles that, so we don't need to check it.
            organization_invitations = load_organization_invitations(user)

            if organization_invitations.present?
              GitHub.logger.info("Found invitations for this organization for User", "gh.copilot.org.invites.count" => organization_invitations.count)
              # they have one or more invitations (in SOME state - we don't care what state)
              # let's see if we have a Seat Assignment pointing to any of them
              invitation_assignments = Copilot::SeatAssignment.where(
                organization: organization,
                assignable_type: "OrganizationInvitation",
                assignable_id: organization_invitations.map(&:id),
                pending_cancellation_date: nil
              )

              if invitation_assignments.present?
                GitHub.logger.info(
                  "OrganizationInvitation SeatAssignment(s) found, creating Seat",
                  "gh.copilot.org.invite_assignments.count" => invitation_assignments.count,
                )
                # we have Copilot::SeatAssignments pointing at one or more of the organization_invitations, so that
                # means we need to give this user a Seat.
                # we will grab the first one and create a Seat for it, and then we will destroy the rest of them
                invitation_assignment = invitation_assignments.first!

                GitHub.logger.info("Removing extra OrganizationInvitation SeatAssignments")

                with_write do
                  invitation_assignments.offset(1).destroy_all
                end

                # Sometimes this job runs before the user is a member of the
                # org, which can cause updating the assignable here to fail.
                #
                # Instead, we use #update_columns to skip the validation, as
                # we trust that the org.add_member event correlates to a user
                # becoming a member of the org.
                #
                # Aren't race conditions fun?
                seat = with_write do
                  invitation_assignment.update_columns(
                    assignable_type: "User",
                    assignable_id: @user_id,
                  )

                  # this SeatAssignment is now a User SeatAssignment
                  # so we need to create a seat for this user since they didn't
                  # have one already
                  Copilot::Seat.create!(
                    seat_assignment: invitation_assignment,
                    organization: organization,
                    assigned_user: user,
                  )
                end
                # instrument that baby
                Copilot::Instrumenter.instrument_copilot_for_business_seat_added(
                  organization,
                  seat.assigned_user_id,
                  @actor,
                  :member_added_organization
                )

                Copilot::SeatManagement::SeatAssignedJob.perform_later(
                  seat.organization_id,
                  seat.assigned_user_id,
                  seat: seat,
                )
                GitHub.logger.info("Seat created for invited organization member",
                                   "gh.copilot.seat.id" => seat.id,
                                   "gh.copilot.seat_assignment.id" => invitation_assignment.id)
                GitHub.dogstats.increment "copilot.organization_member_job.member_changed.org_invite"

                with_write do
                  # Ensure a trial is started when the first seat created for an org with a pending trial is
                  # converted from an OrganizationInvitation.
                  trial = Copilot::BusinessTrial.for_organization(organization)
                  trial.start_trial! if trial&.startable?
                end

                return
              end
            else
              GitHub.logger.info("No Organization/OrganizationInvitation SeatAssignment found")
              GitHub.dogstats.increment "copilot.organization_member_job.member_changed.no_org_or_invite"
            end
          end
        end
      end

      private

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.org.id" => @organization_id,
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
          "gh.actor.id" => @actor_id,
          "gh.invitation.email" => @invitation_email,
        }
        handle_copilot_error(Copilot::Errors::SeatCreationError.new(message), details)
      end

      sig { params(invitee: ::User).returns(T::Array[OrganizationInvitation]) }
      def load_organization_invitations(invitee)
        # so, previously we used the OrganizationInvitation.with_invitee_or_normalized_email method, but that
        # returns an ARRAY of OrganizationInvitations that we need to iterate over and see if the organization
        # matches our organization. This is a bit of a performance hit, so we're going to inline the logic here
        # and see if we can't make it a bit faster.
        lookup_emails = (invitee.emails.map(&:email) + [@invitation_email]).uniq
        emails = UserEmail.safe_bulk_normalize(
          users: invitee,
          emails: lookup_emails,
          verified: true,
          include_private_emails: true,
        )

        with_read do
          OrganizationInvitation.where(
            invitee_id: invitee.id,
            organization_id: @organization_id
          ).or(
            OrganizationInvitation.where(
              normalized_email: emails,
              organization_id: @organization_id,
            )
          ).order(id: :desc).to_ary
        end
      end
    end
  end
end
