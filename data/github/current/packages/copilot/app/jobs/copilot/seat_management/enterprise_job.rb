# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      include Copilot::Helpers
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

      VALID_ACTIONS = T.let(%i[
        remove_organization
        add_organization
      ].freeze, T::Array[Symbol])

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

        if copilot_business.copilot_disabled? && copilot_organization.copilot_configuration_setting_enabled?
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

        with_write do
          copilot_business.propagate_organization_settings!
        end
      end

      # the enterprise removed the organization from the enterprise, we need to see if we can bill directly
      # to the organization.  if not, we need to kill all of the seats.
      sig { void }
      def organization_removed
        copilot_organization = Copilot::Organization.new(T.must(@organization))

        # ok, we can look for a trial and destroy it if any exists
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
            copilot_organization.copilot_plan_downgrade!(false)
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
          # this organization is not billable, so we're just gonna delete all of their seat assignments and seats
          GitHub.logger.info(
            "Organization is not Copilot billable, removing seats if any",
            "gh.billing.payment_method" => copilot_organization.organization_object.payment_method,
            "gh.owner.invoiced" => copilot_organization.organization_object.invoiced?,
          )

          # The following steps may be a noop if we're working with an organization that
          # never had copilot or is already disabled

          with_write do
            Copilot::Seat.for_organization(@organization).each do |seat|
              GitHub.logger.info("Removing seat", "gh.copilot.seat.id" => seat.id)
              seat.cancel!(reason: :organization_removed_from_enterprise) #calling this because it sends notifications to users
            end

            Copilot::SeatAssignment.for_organization(@organization).each do |seat_assignment|
              GitHub.logger.info("Removing seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.destroy!
            end
          end

          with_write do
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
    end
  end
end
