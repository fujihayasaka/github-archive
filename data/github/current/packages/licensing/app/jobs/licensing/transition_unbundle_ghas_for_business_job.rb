# typed: strict
# frozen_string_literal: true

class Licensing::TransitionUnbundleGhasForBusinessJob < ApplicationJob

  queue_as :licensing
  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ->(job) {
    business = job.arguments[0]
    lock_key = "transition_unbundle_ghas_for_business:#{business.customer.id}"
  }

  sig do params(
    business: Business,
    actor: User,
    transition_id: T.nilable(Integer),
    skip_billing_config_changes: T::Boolean
  ).void
  end
  def perform(business, actor:, transition_id: nil, skip_billing_config_changes: false)
    transition = nil
    message = ""

    # On GHEC, we run this transition _before_ `business.advanced_security_products_bundled?` has a new value
    # On GHES, we run the transition _after_ the new license has been uploaded and `business.advanced_security_products_bundled?` has a new value
    # Therefore, we should always run this transition on GHES, regardless of the value of `business.advanced_security_products_bundled?`
    if !business.advanced_security_products_bundled? && !GitHub.enterprise?
      raise "Business is already on unbundled SKUs"
    end

    if transition_id.present?
      transition = Licensing::GhasUnbundleTransition.find(transition_id)
      if transition.present?
        with_write do
          transition.update!(status: "running")
        end
      end
    end

    result = ""

    with_write do
      result = business.unbundle_ghas(actor: actor, skip_billing_config_changes: skip_billing_config_changes) ? "Success" : "Failed"
    end
  rescue => error # rubocop:todo Lint/GenericRescue
    result = error.message
    message = error.message
    GitHub.logger.error(
      exception: error,
      "code.namespace": self.class.name,
      "business.id": business.id,
    )

    Failbot.report(error, { "gh.job.name" => Licensing::TransitionUnbundleGhasForBusinessJob.name })
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

  sig { params(business: Business, result: T.nilable(String)).void }
  def track_transition(business, result)
    success = result == "Success"

    GitHub.dogstats.increment "licensing.transition_unbundle_ghas_for_business",
      tags: ["success:#{success}", "business_id:#{business.id}"]

    business.instrument :ghas_unbundled,
      result: result,
      success: success
  end
end
