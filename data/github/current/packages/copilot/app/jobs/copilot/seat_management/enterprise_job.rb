# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # Note that removing an organization does not mean the organization is being deleted; this code will
    # not interfere with the organization destroy process.
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

      # The enterprise added an organization to the enterprise, so we need to see if the org has any CfB seats
      # or policies set up. if so, we need to enforce the parent enterprise CfB policies on the org.
      sig { void }
      def organization_added
        business = T.must(@enterprise)
        copilot_business = Copilot::Business.new(business)
        copilot_organization = Copilot::Organization.new(T.must(@organization))

        # Always propagate the policy settings of the enterprise down to the organization when it is added.
        with_write do
          GitHub.logger.info("Propagating enterprise settings to organization")
          copilot_business.propagate_organization_settings!
        end

        # Align the enterprise seat management settings with the orgs, if necessary.
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
          # At this point, one of the following is true:
          #
          # - The org and the enterprise have Copilot disabled.
          # - The enterprise has Copilot enabled, and the org does not.
          # - Both have Copilot enabled. If Copilot is enabled for selected orgs, and the newly
          #   added org has Copilot enabled, it is treated as though Copilot was explicitly enabled
          #   for that org.
          #
          # In any of the above cases, we don't touch the org's enablement or seat management settings.
          GitHub.logger.info("Enterprise and org have compatible copilot enablement settings")
        end

        if business.authenticated_through_digital_front_door?
          actor = T.must(::User.find_by(id: @actor_id))
          with_write { copilot_business.create_or_resume_copilot_business_trial(actor, copilot_organization.organization_object) }
        end

        if copilot_business.copilot_enabled_for_all_organizations?
          GitHub.logger.info("Copilot enabled for all organizations, setting business plan")
          # Ensure a Copilot plan is set, defaulting to business, the cheapest option. Don't send emails.
          # Do we need to cancel any pending downgrades here? It should be a no-op, but maybe the UI
          # can get into a weird state?
          with_write do
            copilot_organization.copilot_plan_business!(false)
          end
        end

        unless copilot_organization.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          GitHub.logger.info("Copilot revokable access disabled, exiting")
          return
        end

        GitHub.logger.info("Looking for org-level SeatAssignment to restore")
        # is there an assignment for this org revoked to the enterprise?
        org_assignment = copilot_organization.organization_seat_assignment

        unless org_assignment.present? && org_assignment.access_revoked?
          GitHub.logger.info("No org-level SeatAssignment found")
          return
        end

        GitHub.logger.info("Found revoked org-level SeatAssignment",
          "gh.copilot.seat_assignment.id" => org_assignment.id,
          "gh.copilot.seat_assignment.owner.id" => org_assignment.owner_id,
          "gh.org.id" => copilot_organization.id
        )

        transfer_or_reinstate_assignment!(
          org_assignment,
          copilot_organization,
          copilot_business
        )
      end

      # The enterprise removed the organization from the enterprise.
      # If we cannot bill the org directly, we need to remove all of the seats.
      # I copilot_revokable_access is enabled, we will revoke the seat assignment and assign ownership to the enterprise,
      # so it can continue to be billed for the seats.
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
        should_revoke_access = business.feature_flag_enabled_or_raise?(:copilot_revokable_access) && business.feature_flag_enabled_or_raise?(:copilot_revoke_to_enterprise) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

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
          return
        end

        # This organization is not billable.
        # If copilot_revokable_access is enabled, we will unassign and revoke all their seat assignments.
        # This ensures that the enterprise will continue to get billed for the seats through the end of their billing cycle.
        # If the copilot_revokable_access flag is not enabled, we preserve the existing behavior and delete all of their seat assignments and seats.
        # The following steps may be a noop if we're working with an organization that
        # never had copilot or is already disabled.
        with_write do
          if !should_revoke_access
            GitHub.logger.info(
              "Organization is not Copilot billable, removing seats if any",
              "gh.billing.payment_method" => copilot_organization.organization_object.payment_method,
              "gh.owner.invoiced" => copilot_organization.organization_object.invoiced?,
            )

            Copilot::Seat.for_organization(@organization).each do |seat|
              GitHub.logger.info("Removing seat", "gh.copilot.seat.id" => seat.id)
              seat.cancel!(reason: :organization_removed_from_enterprise) # calling this because it sends notifications to users
            end

            # Because we are removing all the seats, we need to remove all the seat assignments as well.
            Copilot::SeatAssignment.for_organization(@organization).each do |seat_assignment|
              GitHub.logger.info("Removing SeatAssignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.destroy!
            end
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

        # Unless we need to revoke access, we are done here.
        unless should_revoke_access
          GitHub.logger.info("Copilot revokable access disabled, exiting")
          return
        end

        # At this point, if the org had any seats, and copilot_revokable access is enabled,
        # the org should have an org-level seat assignment that is pending cancellation.
        # The call above to seat_management_disable! will create a single seat assignment for the org,
        # with the org itself as the assignable.
        org_assignment = Copilot::SeatAssignment
          .for_owner(copilot_organization.organization_object)
          .where(assignable_type: "Organization")
          .where.not(pending_cancellation_date: nil)
          .first

        unless org_assignment
          GitHub.logger.info("No org-level assignment found, exiting")
          return
        end

        GitHub.logger.info("Got org-level SeatAssignment",
          "gh.copilot.seat_assignment" => org_assignment.attributes
        )

        with_write do
          GitHub.logger.info("Updating owner to business and revoking")
          org_assignment.update_columns(owner_id: business.id, owner_type: "Business")
          org_assignment.unassign_and_revoke_access!(nil, :org_removed_from_enterprise, allow_non_user: true)
        end

        GitHub.logger.info("Finished cleaning up after removed org")
      end

      sig { params(copilot_org: Copilot::Organization, copilot_biz: Copilot::Business).returns(T::Boolean) }
      def copilot_already_enabled_for_org?(copilot_org, copilot_biz)
        return true if copilot_biz.copilot_enabled_for_all_organizations?
        copilot_biz.copilot_enabled_for_selected_organizations? && copilot_org.copilot_configuration_setting_enabled?
      end

      sig { params(assignment: Copilot::SeatAssignment, copilot_org: Copilot::Organization, copilot_biz: Copilot::Business).void }
      def transfer_or_reinstate_assignment!(assignment, copilot_org, copilot_biz)
        is_owned_by_enterprise = assignment.owner_id == copilot_biz.id && assignment.owner_type == "Business"

        params = { owner_id: copilot_org.id, owner_type: "Organization" }

        with_write do
          if copilot_already_enabled_for_org?(copilot_org, copilot_biz)
            # If Copilot is already enabled for the org, we can reinstate the seat assignment.
            assignment.reinstate_access!(
              :copilot_enabled_org_added_to_enabled_enterprise,
              options: {
                allow_non_user: true,
                uncancel: !copilot_org.seat_management_disabled?,
              }.tap { |o| o[:extra_params] = params if is_owned_by_enterprise }
            )
          elsif is_owned_by_enterprise
            # If Copilot is not enabled, we simply update the seat assignment's ownership.
            GitHub.logger.info("Updating ownership of org-level SeatAssignment")
            assignment.update_columns(params)
          else
            GitHub.logger.info("SeatAssignment already owned by org")
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
    end
  end
end
