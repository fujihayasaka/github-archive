# typed: strict
# frozen_string_literal: true

class Licensing::TransitionEnterpriseToMeteredLicensingJob < ApplicationJob

  queue_as :licensing
  retry_on_dirty_exit

  locked_by timeout: 1.minute, key: ->(job) {
    business = job.arguments[0]
    lock_key = "transition_enterprise_to_metered_licensing:#{business.customer.id}"
  }

  sig do params(
    business: Business,
    actor: User,
    trial_upgrade: T.nilable(T::Boolean),
    licensing_model_transition_id: T.nilable(Integer),
    ghas_only: T.nilable(T::Boolean),
    reset_ghas_configuration: T.nilable(T::Boolean),
    unbundle_ghas: T.nilable(T::Boolean)
  ).void
  end
  def perform(business, actor:, trial_upgrade: false, licensing_model_transition_id: nil, ghas_only: false, reset_ghas_configuration: false, unbundle_ghas: false)
    transition = nil
    message = ""

    if licensing_model_transition_id.present?
      transition = Licensing::LicensingModelTransition.find(licensing_model_transition_id)
      ghas_only = transition.ghas_only
      reset_ghas_configuration = transition.reset_ghas_configuration
    end

    unless trial_upgrade
      # guard from proceeding, and let rescue block instrument the reason
      raise "Business is already on metered GHE" if business.metered_plan? && !ghas_only
      raise "Business is already on metered GHAS" if business.advanced_security_metered_for_entity? && ghas_only
    end

    if licensing_model_transition_id.present?
      transition = Licensing::LicensingModelTransition.find(licensing_model_transition_id)
      if transition.present?
        with_write do
          transition.update!(status: "running")
        end
      end
    end

    # The onboarding job won't change the GHAS offering if there's already one in place,
    # and in general we should rely on that job to own GHAS enablement...we only want it
    # to own onboarding the GHAS product to the billing platform.
    result = ""
    with_write do
      result = business.enable_metered_product_suite(actor: actor, ghas_only: ghas_only, reset_ghas_configuration: reset_ghas_configuration) ? "Success" : "Failed"
    end
  rescue => error # rubocop:todo Lint/GenericRescue
    result = error.message
    message = error.message
    GitHub.logger.error(
      exception: error,
      "code.namespace": self.class.name,
      "business.id": business.id,
    )

    Failbot.report(error, { "gh.job.name" => Licensing::TransitionEnterpriseToMeteredLicensingJob.name })
  ensure
    track_transition(business, result)
    if transition.present?
      with_write do
        transition.update!(
          message: message,
          status: result == "Success" ? "success" : "failed"
        )
      end
    end
  end

  private

  sig { returns(GitHub::Restraint) }
  def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end

  sig { params(business: Business, result: T.nilable(String)).void }
  def track_transition(business, result)
    success = result == "Success"

    GitHub.dogstats.increment "licensing.transition_enterprise_to_metered_licensing",
      tags: ["success:#{success}", "business_id:#{business.id}"]

    business.instrument :change_licensing_model,
      old_licensing_model: "Volume",
      licensing_model: "Metered",
      result: result,
      success: success
  end
end
