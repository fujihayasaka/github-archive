# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class GhasTrial

    attr_reader :actor, :api_access, :billable_entity

    def initialize(actor:, billable_entity:, api_access: false)
      @actor = actor
      @api_access = api_access
      @billable_entity = billable_entity

      # Use the enterprise as the actor if the organization belongs to an enterprise
      if billable_entity.organization? && billable_entity.delegate_billing_to_business?
        @billable_entity = billable_entity.business
      end

      if !@billable_entity.is_a?(Organization) && !@billable_entity.is_a?(Business)
        raise ArgumentError, "Invalid organization from type: #{billable_entity.class}"
      end
    end

    def enable(number_of_days = 30, sfdc_poc_url: "")
      return unless allowed_ghas_trial_conditions?
      return if billable_entity.advanced_security_purchased_for_entity?

      ActiveRecord::Base.connected_to(role: :writing) do
        billable_entity.enable_advanced_security_trial_for_entity(actor: actor)
        billable_entity.set_advanced_security_trial_number_of_days(actor: actor, days: number_of_days)
        billable_entity.set_advanced_security_trial_expires_at(actor: actor, date: Date.current + number_of_days.days)
        billable_entity.mark_advanced_security_as_purchased_for_entity(actor: actor)

        # Should we limit the number of seats in the GHAS trial?
        # For now we are not limiting seats
        billable_entity.set_advanced_security_seats_for_entity(seats: 0, actor: actor)

        if billable_entity.organization?
          enable_ghas_features_on_demo_repo(billable_entity)
        elsif billable_entity.is_a?(Business)
          billable_entity.organizations.find_each do |organization|
            enable_ghas_features_on_demo_repo(organization)
          end
        end
      end

      message = {
        enterprise_id: billable_entity.is_a?(Business) ? billable_entity.id : nil,
        organization_id: billable_entity.is_a?(Organization) ? billable_entity.id : nil,
        action: :STARTED,
        trial_sku: :ADVANCED_SECURITY,
        start_method: :API,
        sfdc_poc_url:,
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
    end

    def enabled?
      billable_entity.advanced_security_trial_enabled_for_entity?
    end

    def disable
      return if GitHub.enterprise?

      # Only disable if the trial is still in trial state. Do not disable if the trial has been purchased (e.g. moved to >0 seats)
      if billable_entity.advanced_security_license.has_sales_serve_trial?
        billable_entity.mark_advanced_security_as_not_purchased_for_entity(actor: actor)
      end

      if billable_entity.advanced_security_trial_enabled_for_entity?
        billable_entity.disable_advanced_security_trial_for_entity(actor: actor)
        billable_entity.delete_advanced_security_trial_number_of_days(actor: actor)
      end

      message = {
        enterprise_id: billable_entity.is_a?(Business) ? billable_entity.id : nil,
        organization_id: billable_entity.is_a?(Organization) ? billable_entity.id : nil,
        action: :ENDED,
        trial_sku: :ADVANCED_SECURITY,
        converted_to_paid: billable_entity.advanced_security_purchased?,
        **billable_entity.advanced_security_usage_stats
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
    end

    def prolong(extended_number_of_days)
      return unless allowed_ghas_trial_conditions?
      return unless billable_entity.advanced_security_purchased_for_entity?

      trial_number_of_days = billable_entity.advanced_security_trial_number_of_days
      billable_entity.set_advanced_security_trial_number_of_days(
        actor: actor,
        days: trial_number_of_days + extended_number_of_days
      )
      billable_entity.extend_advanced_security_trial_expires_at(extended_days: extended_number_of_days, actor: actor)
    end

    def expires_at
      return unless billable_entity.advanced_security_trial_enabled_for_entity?
      billable_entity.get_advanced_security_trial_expires_at
    end

    def expired?
      return unless expires_at.is_a?(Date)
      expires_at <= Date.today
    end

    private

    def enable_ghas_features_on_new_repos(organization)
      return unless organization.organization?

      organization.enable_advanced_security_on_new_repos(actor: actor)
      SecretScanning::Features::Org::TokenScanning.new(organization).enable_secret_scanning_for_new_repos(actor: actor)

      # I thnk this is not a GHAS feature, since its the same used in public repos? Should we remove it?
      organization.enable_security_alerts_for_new_repos(actor: actor)
    end

    def enable_ghas_features_on_demo_repo(organization)
      return unless organization.organization?

      response = OrganizationOnboard::DemoRepository.enable_ghas_and_secret_scanning(organization, actor)
      if response.error?
        GitHub.logger.warn("Attempted to enable GHAS features on demo repo",
          "gh.actor.login": actor.login,
          "gh.org.login": organization.login,
          "gh.demo_repository.ghas_features_status": "failed",
          "exception.message": response.error,
        )
      else
        GitHub.logger.warn("Enabled GHAS features on demo repo",
          "gh.actor.login": actor.login,
          "gh.org.login": organization.login,
          "gh.demo_repository.ghas_features_status": "success",
        )
      end

      response
    end

    def allowed_ghas_trial_conditions?
      return if GitHub.enterprise?
      return unless actor
      return if !billable_entity.adminable_by?(actor) && !api_access
      true
    end
  end
end
