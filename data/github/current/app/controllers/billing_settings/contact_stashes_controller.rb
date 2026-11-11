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
    Billing::ContactUpdateStash.stash_update_for(target, contact_type, contact_information_params)

    head :ok
  end

  private

  sig { returns(String) }
  def contact_type
    params[:contact_type] || "billing"
  end

  sig { void }
  def ensure_target
    render_404 if target.nil?
  end

  sig { returns(ActionController::Parameters) }
  def contact_information_params
    params.require(:contact_information).permit(
      :first_name,
      :last_name,
      :middle_name,
      :region,
      :city,
      :country_code,
      :postal_code,
      :address1,
      :address2,
      :entity_name,
      :vat_code,
    )
  end
end
