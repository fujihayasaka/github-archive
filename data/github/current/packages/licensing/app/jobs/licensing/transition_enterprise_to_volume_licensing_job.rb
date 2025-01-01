# typed: strict
# frozen_string_literal: true

class Licensing::TransitionEnterpriseToVolumeLicensingJob < ApplicationJob
  extend T::Sig
  SKU = T.let("ghec_seats".freeze, String)

  retry_on(Billing::Platform::Api::Error, wait: :polynomially_longer, attempts: 5) do |_job, error|
    Failbot.report(error)
  end

  locked_by timeout: 30.minutes, key: DEFAULT_LOCK_PROC

  queue_as :licensing
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(business: Business, licensing_model_transition_id: T.nilable(Integer)).void }
  def perform(business, licensing_model_transition_id: nil)
    # validate the business is configured for volume billing + licensing
    raise "Business is already on a volume plan" unless business.metered_plan?
    message = ""
    transition = nil

    if licensing_model_transition_id.present?
      transition = Licensing::LicensingModelTransition.find(licensing_model_transition_id)
      if transition.present?
        with_write do
          transition.update!(status: "running")
        end
      end
    end

    client = Billing::Platform::Api::Client.new
    customer_id = business.customer_id.to_s
    ghec_subscriptions = client.get_subscribed_items(usage_entity_id: customer_id, sku: SKU)

    # We don't want to continue if we can't get the subscriptions.
    raise ghec_subscriptions if ghec_subscriptions.is_a?(Billing::Platform::Api::Error)

    GitHub.tracer.in_span("Licensing::TransitionEnterpriseToVolumeLicensingJob#perform.remove_ghec_subscriptions", attributes: { "business.customer_id" => customer_id }) do |_span|
      ghec_subscriptions[:subscribedItems].each do |subscriber|
        result = client.remove_license(
          sku: SKU,
          subscription_at: Time.now.to_i,
          entity_detail: {
            customerId: customer_id,
            actorId: subscriber[:subscriptionId],
          }
        )

        # We don't want to continue if we can't remove all licenses
        raise result if result.is_a?(Billing::Platform::Api::Error)
      end
    end

    Billing::OffboardCustomerFromProductInBillingPlatformJob.perform_now(
      customer_id: T.must(T.must(business.customer).id),
      product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize,
    )

    BusinessUserAccountUpdateAttributesJob.enqueue(business)

    with_write do
      BusinessUserAccount.where(business: business).update_all(ghec_license: nil)
      T.must(business.customer).update!(metered_ghe: false)
    end

    result = "Success"
  rescue => error # rubocop:todo Lint/GenericRescue
    result = "Unable to transition to volume licensing"
    raise if error.class.in?([Billing::Platform::Api::Error])

    result = error.message

    GitHub.logger.error(
      exception: error,
      "code.namespace": self.class.name,
      "business.id": business.id,
    )

    Failbot.report(error, { "gh.job.name" => Licensing::TransitionEnterpriseToVolumeLicensingJob.name })

    result = error.message

    message = error.message
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

  sig { params(business: Business, result: T.nilable(String)).void }
  def track_transition(business, result)
    success = result == "Success"

    GitHub.dogstats.increment "licensing.transition_enterprise_to_volume_licensing",
      tags: ["success:#{success}", "business_id:#{business.id}"]

    business.instrument :change_licensing_model,
      old_licensing_model: "Metered",
      licensing_model: "Volume",
      result: result,
      success: success
  end
end
