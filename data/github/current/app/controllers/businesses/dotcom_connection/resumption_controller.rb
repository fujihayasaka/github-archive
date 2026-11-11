# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnection::ResumptionController < Businesses::BusinessController
  include Businesses::DotcomConnection::ControllerMethods

  before_action :business_owner_required
  before_action :require_dotcom_connection_enabled

  def create
    if token = dotcom_connection.temp_authentication_token
      redirect_to dotcom_enterprise_installation_url(token, current_state)
    else
      redirect_error
    end
  end
end
