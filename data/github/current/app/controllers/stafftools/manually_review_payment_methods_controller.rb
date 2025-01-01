# typed: strict
# frozen_string_literal: true

class Stafftools::ManuallyReviewPaymentMethodsController < StafftoolsController
  extend T::Sig

  sig { void }
  def update
    payment_method = PaymentMethod.find(params[:id])

    payment_method.update!(
      manually_reviewed_at: Time.now,
      manually_reviewed_by_id: current_user.id
    ) unless payment_method.manually_reviewed?

    redirect_to lookup_stafftools_reused_card_fingerprints_path(card_fingerprint: payment_method.card_fingerprint)
  end
end
