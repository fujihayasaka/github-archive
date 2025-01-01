# typed: true
# frozen_string_literal: true

class Businesses::OpenSCIMConfigurationController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :emu_business_required, only: %i[create]

  def create
    if params[:value] == "1"
      this_business.enable_open_scim(actor: current_user)
    else
      this_business.disable_open_scim(actor: current_user)
    end
    redirect_to :back
  end
end
