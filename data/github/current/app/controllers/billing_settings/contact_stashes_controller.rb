# typed: strict
# frozen_string_literal: true

class BillingSettings::ContactStashesController < ApplicationController

  include Contacts::SharedControllerMethods
  include TradeControlsControllerMethods

  before_action :login_required
  before_action :ensure_target

  sig { void }
  def create
    return render_404 unless request.xhr?
    target = T.must(self.target)

    Billing::ContactUpdateStash.stash_update_for(
      target, target.billing_contact.address_type, account_screening_profile_params.except(:org_record_is_individual_owned)
    ) if params.has_key?(:account_screening_profile)

    Billing::ContactUpdateStash.stash_update_for(
      target, target.billing_contact.address_type, billing_contact_params.except(:org_record_is_individual_owned)
    ) if params.has_key?(:billing_contact)

    Billing::ContactUpdateStash.stash_update_for(
      target, target.shipping_contact.address_type, shipping_contact_params.except(:org_record_is_individual_owned)
    ) if params.has_key?(:shipping_contact)

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
