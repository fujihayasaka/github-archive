# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # Note that removing an organization does not mean the organization is being deleted; this code will
    # not interfere or cause a race condition with the organization destroy process.
    # This job only handles the case in which an organization is removed from the parent enterprise and
    # converted into a standalone org.
    class EnterpriseJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatAssignments::SeatCreation

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

      VALID_ACTIONS = T.let(%i[
        remove_organization
        add_organization
      ].freeze, T::Array[Symbol])

      resolve_tenant_context do |args|
        ::Business.find_by(id: args[:enterprise_id])
      end

      sig do
        params(
          actor_id: T.nilable(Integer),
          enterprise_id: Integer,
          organization_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def perform(actor_id:, enterprise_id:, organization_id:, action: :unknown, transaction_id: nil, payload: nil)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
          "gh.copilot.job_action" => action,
          "gh.transaction.id" => transaction_id,
          "gh.actor.id" => actor_id,
          "gh.business.id" => enterprise_id,
        ) do
          @actor_id        = T.let(actor_id, T.nilable(Integer))
          @enterprise_id   = T.let(enterprise_id, T.nilable(Integer))
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped

          # load up the organization - this is required so if it isn't there, report an exception. We might want to tweak this later
          @organization = T.let(::Organization.find_by(id: T.must(@organization_id)), T.nilable(::Organization))
          return report_error("Invalid Organization") unless @organization

          # load up the ENTERPRISE - this is required so if it isn't there, report an exception. We might want to tweak this later
          @enterprise = T.let(::Business.find_by(id: T.must(@enterprise_id)), T.nilable(::Business))
          return report_error("Invalid Enterprise") unless @enterprise

          @actor = T.let(::User.find_by(id: @actor_id), T.nilable(::User))

          GitHub.dogstats.distribution_time("copilot.seat_management.enterprise_job.duration") do
            GitHub.logger.info("Processing action #{action}")
            case action
            when :remove_organization
              organization_removed
            when :add_organization
              organization_added
            else
              raise ArgumentError, "Invalid action: #{action}"
            end
          end
        end
      end

      # the enterprise added an organization to the enterprise, so we need to see if the org has any CfB seats
      # or policies set up. if so, we need to enforce the parent enterprise CfB policies on the org.
      sig { void }
      def organization_added
        copilot_business = Copilot::Business.new(T.must(@enterprise))
        copilot_organization = Copilot::Organization.new(T.must(@organization))

        if !copilot_business.copilot_enabled? && copilot_organization.copilot_configuration_setting_enabled?
          GitHub.logger.info("Enterprise has Copilot fully disabled, disabling org's seats")

          with_write do
            # this also instruments seat_management_changed
            copilot_organization.revoke_copilot_for_org!
          end

          CopilotForBusinessMailer.cfb_disabled_by_business(
            T.must(@enterprise),
            T.must(@organization)
          ).deliver_later
        else
          GitHub.logger.info("Enterprise and org have compatible seat management, skipping org seat updates")
        end

        business = copilot_business.business_object
        if business.authenticated_through_digital_front_door?
          actor = T.must(::User.find_by(id: @actor_id))
          with_write { copilot_business.create_or_resume_copilot_business_trial(actor, copilot_organization.organization_object) }
        end

        with_write do
          copilot_business.propagate_organization_settings!

          if copilot_business.copilot_enabled_for_all_organizations?
            # Ensure a Copilot plan is set. Default to business as it is the cheapest option.
            # Don't send emails.
            copilot_organization.copilot_plan_business!(false)
          end
        end

        # Finally, trigger the reinstatement job for the organization. If there were any
        # previously revoked seats, we will unrevoke, and potentially uncancel them.
        Copilot::SeatManagement::OrgAccessReinstatementJob.perform_later(
          org_id: T.must(@organization_id),
          reason: :org_added_to_enterprise
        )
      end

      # the enterprise removed the organization from the enterprise, we need to see if we can bill directly
      # to the organization.  if not, we need to kill all of the seats.
      sig { void }
      def organization_removed
        copilot_business = Copilot::Business.new(T.must(@enterprise))
        copilot_organization = Copilot::Organization.new(T.must(@organization))

        # ok, we can look for an Enterprise plan trial and destroy it if any exists
        if copilot_organization.business_trial&.copilot_plan_enterprise? && copilot_organization.business_trial&.ongoing?
          trial = T.must(copilot_organization.business_trial)
          with_write do
            GitHub.logger.info(
              "Destroying Copilot business trial",
              "gh.copilot.trial.id" => trial.id,
              "gh.copilot.trial.state" => trial.state,
              "gh.copilot.trial.trial_length" => trial.trial_length,
              "gh.copilot.trial.ends_at" => trial.ends_at,
            )
            trial.destroy!
          end
        end

        # Whether they are billable or not, we need to downgrade this org to Copilot Business
        # if they have a Copilot Enterprise plan while linked to a parent business.
        if copilot_organization.copilot_plan_enterprise?
          with_write do
            # Skip sending an email to org entities as a result of the downgrade.
            copilot_organization.copilot_plan_downgrade!(false)
          end
        end

        business = copilot_business.business_object
        should_revoke_access = business.feature_enabled?(:copilot_revokable_access)

        # Next, we look to see if the enterprise itself is on a trial, and if the organization being
        # removed has a Copilot Business plan trial.
        # If it does, we should cancel it.
        copilot_org_business_trial = copilot_organization.business_trial
        if business.trial? && copilot_org_business_trial && copilot_org_business_trial.ongoing?
          with_write do
            # We don't need to revoke access here because the business itself is also on a trial — there is no
            # reason to continue billing in this case.
            copilot_org_business_trial.cancel!
          end
        end

        if copilot_organization.copilot_billable?
          # we aren't going to change anything here actually. they are just gonna start getting billed directly
          GitHub.logger.info(
            "Organization is Copilot billable, keeping seats if any",
            "gh.billing.payment_method" => copilot_organization.organization_object.payment_method,
            "gh.owner.invoiced" => copilot_organization.organization_object.invoiced?,
          )
        else
          # This organization is not billable.
          # If copilot_revokable_access is enabled, we will unassign and revoke all their seat assignments.
          # This ensures that the enterprise will continue to get billed for the seats through the end of their billing cycle.
          # If the flag is not enabled, we preserve the existing behavior and delete all of their seat assignments and seats.
          GitHub.logger.info(
            "Organization is not Copilot billable, removing seats if any",
            "gh.billing.payment_method" => copilot_organization.organization_object.payment_method,
            "gh.owner.invoiced" => copilot_organization.organization_object.invoiced?,
          )

          # The following steps may be a noop if we're working with an organization that
          # never had copilot or is already disabled.
          with_write do
            if should_revoke_access
              GitHub.logger.info("Removing seats and disassociating user assignments from organization")
              create_and_revoke_disassociated_user_assignments
            else
              Copilot::Seat.for_organization(@organization).each do |seat|
                GitHub.logger.info("Removing seat", "gh.copilot.seat.id" => seat.id)
                seat.cancel!(reason: :organization_removed_from_enterprise) # calling this because it sends notifications to users
              end
            end

            # Because we are removing all the seats, we need to remove all the seat assignments as well.
            # Note that this occurs even when we create disassociated seat assignments, as we are creating
            # new seats for the disassociated seat assignments.
            Copilot::SeatAssignment.for_organization(@organization).each do |seat_assignment|
              GitHub.logger.info("Removing seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.destroy!
            end

            copilot_organization.disable_copilot! unless copilot_organization.copilot_disabled?

            # we don't want to do anything if seat management is already disabled or unconfigured, otherwise
            # we may end up creating an organization seat assignment for an organization that has nothing to do with copilot
            unless copilot_organization.seat_management_disabled?
              old_seat_management_setting = copilot_organization.seat_management_setting

              copilot_organization.seat_management_disable!

              Copilot::Instrumenter.instrument_copilot_for_business_seat_management_changed(
                nil,
                T.must(@organization),
                old_seat_management_setting,
                "disabled"
              )
            end
          end
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.actor.id" => @actor_id,
          "gh.business.id" => @enterprise_id,
        }
        handle_copilot_error(Copilot::Errors::EnterpriseJobError.new(message), details)
      end

      sig { void }
      def create_and_revoke_disassociated_user_assignments
        org_seats = with_read do
          Copilot::Seat.for_organization(@organization)
        end

        # Get all unique users whose access we are revoking.
        users_with_seats = org_seats.map(&:assigned_user_id).uniq

        users_to_disassociate = T.let([], T::Array[Integer])

        with_read do
          # Get all users who already have a disassociated seat assignment for this enterprise.
          # This may have happened if e.g. the user had another seat disassociated from an org team in an
          # earlier job run.
          # Their assignment will always be a user-level assignment, because enterprises with
          # organizations do not have enterprise teams.
          # Just get all the records, otherwise we run the risk of a query with potentially thousands of
          # ids in a WHERE IN clause.
          users_with_assignments = Copilot::SeatAssignment.where(
            owner_id: @enterprise_id,
            owner_type: "Business",
            assignable_type: "User"
          ).pluck(:assignable_id)

          # Find the difference between the two lists of user ids.
          users_to_disassociate = users_with_seats - users_with_assignments
        end

        # Blow away all the seats, rather than repointing them in individual writes.
        with_write { org_seats.destroy_all }

        return if users_to_disassociate.empty?

        revoke_time = Time.now
        assignment_params = users_to_disassociate.map do |user_id|
          {
            owner_id: @enterprise_id,
            owner_type: "Business",
            assignable_type: "User",
            assignable_id: user_id,
            assigning_user_id: @actor&.id,
            pending_cancellation_date: T.must(@enterprise).next_metered_billing_cycle_starts_at,
            access_revoked_at: revoke_time,
            created_at: revoke_time
          }
        end

        batch_insert(assignment_params, Copilot::SeatAssignment)

        created_assignments = T.let([], T::Array[T::Array[Integer]])

        with_read do
          # Inserting in bulk doesn't return the ids of the inserted records, so we need to query for them.
          # We are querying based on the creation time, which should generally limit us to records that were just created.
          # Furthermore, we exclude any records that already have a seat, both to limit incorrect results and to avoid creating
          # duplicate seats.
          created_assignments = ApplicationRecord::Domain::Copilot.connection.select_rows(Arel.sql(<<-SQL, owner_id: @enterprise_id, created: revoke_time.utc))
            SELECT csa.id, csa.assignable_id
            FROM copilot_seat_assignments csa
            LEFT JOIN copilot_seats cs ON cs.copilot_seat_assignment_id = csa.id
            WHERE csa.owner_id = :owner_id
            AND csa.owner_type = 'Business'
            AND csa.assignable_type = 'User'
            AND csa.created_at = :created
            AND csa.access_revoked_at = :created
            AND cs.id IS NULL
          SQL
        end

        seat_inserts = created_assignments.map do |seat_assignment_id, assignable_id|
          GitHub.logger.info(
            "Creating new seat pointing to disassociated user assignment",
            "gh.copilot.seat_assignment.id" => seat_assignment_id,
            "gh.user.id" => assignable_id
          )

          {
            copilot_seat_assignment_id: T.must(seat_assignment_id),
            assigned_user_id: T.must(assignable_id),
            organization_id: nil
          }
        end

        GitHub.logger.info("Inserting new seats pointing to disassociated user assignments")
        write_seats(seat_inserts, @actor, T.must(@enterprise), false)
      end

      sig do
        params(
          records: T::Array[T::Hash[Symbol, T.any(String, Integer, Time, ActiveSupport::TimeWithZone)]],
          klass: T.any(T.class_of(Copilot::Seat), T.class_of(Copilot::SeatAssignment)),
          batch_size: Integer
        ).void
      end
      def batch_insert(records, klass, batch_size = 1000)
        records.in_groups_of(batch_size, false) do |batch|
          klass.throttle_writes do
            klass.insert_all(batch)
          end
        end
      end
    end
  end
end
