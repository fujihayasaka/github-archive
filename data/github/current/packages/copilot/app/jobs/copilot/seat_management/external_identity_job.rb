# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class ExternalIdentityJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::SeatAssignments::SeatCreation
      include Copilot::Helpers
      gate_with_feature_flag %i(copilot_seat_assignment_job copilot_external_identity_job)

      resolve_tenant_context do |args|
        user_id = args[:user_id]
        ::User.find_by(id: user_id)&.enterprise_managed_business
      end

      sig do
        params(
          user_id: Integer,
          external_identity_id: Integer,
          transaction_id: T.nilable(String),
          action: Symbol,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(user_id:, external_identity_id:, transaction_id: nil, action: :unknown, payload: nil, actor_id: nil)
        payload ||= {}

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.action" => action,
          "gh.copilot.external_identity.external_id" => payload.fetch(:external_identity_external_id, "unknown"),
          "gh.copilot.external_identity.id" => external_identity_id,
          "gh.copilot.external_identity.provider_type" => payload.fetch(:provider_type, "unknown"),
          "gh.copilot.job_action" => action,
          "gh.copilot.operation" => payload.fetch(:operation, :unknown),
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @user_id              = T.let(user_id, T.nilable(Integer))
          @action               = T.let(action, T.nilable(Symbol))
          @transaction_id       = T.let(transaction_id, T.nilable(String))
          @payload              = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @external_identity_id = T.let(external_identity_id, T.nilable(Integer))
          @actor                = T.let(::User.find_by(id: actor_id), T.nilable(::User))
          @existing_seat_owner_ids = T.let([], T.nilable(T::Array[Integer]))

          case action
          when :provision
            handle_provision_event(user_id, external_identity_id)
          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      sig { params(user_id: Integer, external_identity_id: Integer).void }
      def handle_provision_event(user_id, external_identity_id)
        return unless FeatureFlag.vexi.enabled?(:copilot_external_identity_job_handle_provision, default: true)

        GitHub.logger.with_named_tags(
          "code.function" => "handle_provision_event",
          "gh.user.id" => @user_id,
          "gh.external_identity.id" => @external_identity_id) do
          # let's load up the external identity
          external_identity = ExternalIdentity.find_by(id: external_identity_id)

          unless external_identity
            # we have nothing to do here
            GitHub.logger.error("External identity not found")
            return # crying
          end

          unless external_identity.user_id == user_id
            # we have nothing to do here
            GitHub.logger.error("External identity and user do not match")

            Copilot::ErrorReporter.report!(
              Copilot::Errors::ExternalIdentityUserMismatchError.new("External identity and user do not match"),
              extra_details: {
                :action => @action,
                :transaction_id => @transaction_id,
                :payload => @payload,
                "gh.user.id" => @user_id,
                "gh.external_identity.id" => @external_identity_id,
              }
            )
            return # weeping
          end

          # okay, we have a user, let's look and see if any of the business' organizations has a seat assignment
          # that affects this User
          # we do not do anything for EnterpriseTeams here YET
          user = T.must(external_identity.user)

          GitHub.logger.info("Processing Copilot seat assignments for provisioned user.")

          # this can be an organization or a business based on the VALID_PROVIDER_TYPES in ExternalIdentity
          # either way, we want the organization ids
          organization_ids = if external_identity.target.is_a?(::Organization)
            [external_identity.target.id]
          elsif external_identity.target.is_a?(::Business)
            external_identity.target.organization_ids
          else
            []
          end

          # I think we'd hit an ActiveSupport error before we got here
          if organization_ids.empty?
            GitHub.logger.info("Provisioned user has no organizations")
            return
          end

          with_read do
            # this user could be a member of multiple organizations.
            # one of those organizations could have allowed the entire organization
            # let's check
            org_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.organization_ids,
              assignable_type: "Organization",
              owner_type: "Organization",
              owner_id: organization_ids,
            )

            if org_assignments.any?
              insert_seats_for_assignments(user, org_assignments)
            else
              GitHub.logger.info("User's organizations have no org level seat assignments")
            end

            # this user could be a member of multiple teams, so let's see if any of those have been assigned
            team_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.team_ids,
              assignable_type: "Team",
              owner_type: "Organization",
              owner_id: organization_ids
            )

            if team_assignments.any?
              insert_seats_for_assignments(user, team_assignments)
            else
              GitHub.logger.info("User's teams have no team level seat assignments")
            end

            # the user could be individually assigned so we'll check those
            user_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.id,
              assignable_type: "User",
              owner_type: "Organization",
              owner_id: organization_ids,
            )

            if user_assignments.any?
              insert_seats_for_assignments(user, user_assignments)
            else
              GitHub.logger.info("User has no user level seat assignments")
            end
          end
        end
      end

      private

      sig { params(user: ::User, seat_assignments: ActiveRecord::Relation).void }
      def insert_seats_for_assignments(user, seat_assignments)
        seat_assignments.each do |seat_assignment|
          assignable_type = seat_assignment.assignable_type

          # we want to create a new seat pointing at this seat assignment unless the user already has another seat for the owner
          # (i.e. got a seat when the org was re-converted or has already had a seat created for a different team in this org during this job
          existing_seat = Copilot::Seat.for_assigned_user_and_owner(user, seat_assignment.owner).first

          # only log/stat once per owner
          if existing_seat.present?
            if !@existing_seat_owner_ids&.include?(seat_assignment.owner_id)
              GitHub.dogstats.increment("copilot.external_identity_job.seat_exists", tags: ["type:#{existing_seat.seat_assignment&.assignable_type.underscore}"])
              GitHub.logger.info("User already has a seat for this #{seat_assignment.owner&.type}",
                "gh.copilot.seat.id" => existing_seat.id,
                "gh.copilot.seat_assignment.id" => seat_assignment.id,
                "gh.copilot.seat_assignment.assignable_type" => assignable_type,
                "gh.copilot.seat_assignment.owner_id" => seat_assignment.owner_id,
                "gh.copilot.seat_assignment.owner_type" => seat_assignment.owner_type
              )
            end
            @existing_seat_owner_ids &.<< seat_assignment.owner_id

            # TODO: reinstate assignment if it is a revoked user assignment?

            next
          end

          GitHub.logger.info("Processing #{assignable_type} seat assignment for provisioned user",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.assignable_type" => assignable_type,
            "gh.copilot.seat_assignment.owner_id" => seat_assignment.owner_id,
            "gh.copilot.seat_assignment.owner_type" => seat_assignment.owner_type
          )

          # we're not calling convert_to_seats on the seat assignment so we don't mess with the rest of the team/org unnecessarily
          # and do a bunch of extra queries we don't care about. We'll take most of the steps the converter commands do, though.
          valid_seat_assignment = ensure_convertible!(seat_assignment, seat_assignment.symbolized_assignable_type.upcase)
          if valid_seat_assignment.nil?
            GitHub.dogstats.increment("copilot.external_identity_job.assignment_not_convertible", tags: ["type:#{assignable_type.underscore}"])
            GitHub.logger.info("Seat assignment is not convertible")
            next
          end

          insert_seats([{
            assigned_user_id: user.id,
            copilot_seat_assignment_id: valid_seat_assignment.id,
            organization_id: valid_seat_assignment.owner_id
          }], seat_assignment, actor: @actor)

          GitHub.dogstats.increment("copilot.external_identity_job.seat_inserted", tags: ["type:#{assignable_type.underscore}"])
          GitHub.logger.info("Inserted seat for provisioned user",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.assignable_type" => assignable_type,
            "gh.copilot.seat_assignment.owner_id" => seat_assignment.owner_id,
            "gh.copilot.seat_assignment.owner_type" => seat_assignment.owner_type,
          )
        end
      end
    end
  end
end
