# typed: strict
# frozen_string_literal: true

class SdnLlama::BillingInfoComponent < ApplicationComponent
  include TradeControlsHelper

  private

  sig { returns(T::Boolean) }
  def hide_name_address_collection_wrapper?
    has_saved_billing_information?
  end

  sig { returns(Billing::Types::BillingInformation) }
  def billing_contact
    current_user.billing_contact
  end

  sig { returns(T::Boolean) }
  def show_request_in_review_notice?
    current_user.has_requested_llama2_access?
  end

  sig { returns(T::Boolean) }
  memoize def has_saved_billing_information?
    current_user.has_saved_billing_information?
  end
end
