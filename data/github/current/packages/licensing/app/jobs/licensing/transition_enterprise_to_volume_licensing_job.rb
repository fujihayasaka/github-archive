# typed: strict
# frozen_string_literal: true

class Licensing::TransitionEnterpriseToVolumeLicensingJob < ApplicationJob
  retry_on(Billing::Platform::Api::Error, wait: :polynomially_longer, attempts: 5) do |_job, error|
    Failbot.report(error)
  end

  locked_by timeout: 30.minutes, key: DEFAULT_LOCK_PROC

  queue_as :licensing
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(business: Business, licensing_model_transition_id: T.nilable(Integer), coupon_code: T.nilable(String), ghas_only: T.nilable(T::Boolean)).void }
  def perform(business, licensing_model_transition_id: nil, coupon_code: nil, ghas_only: false)
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

    if ghas_only
      Billing::OffboardCustomerFromProductInBillingPlatformJob.perform_now(
        customer_id: T.must(business.customer).id,
        product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize,
      )
    else
      # validate the business is configured for volume billing + licensing
      raise "Business is already on a volume plan" unless business.metered_plan?

      Billing::OffboardCustomerFromProductInBillingPlatformJob.perform_now(
        customer_id: T.must(business.customer).id,
        product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize,
      )

      BusinessUserAccountUpdateAttributesJob.enqueue(business)

      with_write do
        T.must(business.customer).update!(metered_ghe: false)
        business.redeem_coupon(coupon_code, { actor: transition&.actor }) if coupon_code.present?
        BusinessUserAccount.where(business: business).update_all(ghec_license: nil)
        business.update!(seats: [business.subscription.seats, business.consumed_enterprise_licenses].compact.max)
      end
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

  private

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
