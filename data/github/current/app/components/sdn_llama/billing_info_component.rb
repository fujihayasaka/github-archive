# typed: strict
# frozen_string_literal: true

class SdnLlama::BillingInfoComponent < ApplicationComponent
  include TradeControlsHelper

  private

  sig { returns(T::Boolean) }
  def hide_name_address_collection_wrapper?
    has_saved_trade_screening_record?
  end

  sig { returns(AccountScreeningProfile) }
  def trade_screening_record
    current_user.trade_screening_record
  end

  sig { returns(T::Boolean) }
  def show_request_in_review_notice?
    trade_screening_record.owner_has_requested_llama2_access?
  end

  sig { returns(T::Boolean) }
  memoize def has_saved_trade_screening_record?
    current_user.has_saved_trade_screening_record?
  end
end
