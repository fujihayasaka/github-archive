# typed: strict
# frozen_string_literal: true

class TradeScreeningBillingInfoStashController < ApplicationController
  extend T::Sig

  include TradeControlsControllerMethods

  before_action :login_required
  before_action :ensure_target

  sig { void }
  def create
    return render_404 unless request.xhr?

    Billing::Settings::AccountScreeningProfileUpdateStash.stash_update_for(
      target, account_screening_profile_params.except(:org_record_is_individual_owned)
    )
    head :ok
  end

  private

  sig { returns(T.nilable(T.any(::Billing::Types::Account, Symbol))) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  sig { void }
  def ensure_target
    render_404 if target.nil?
  end
end
