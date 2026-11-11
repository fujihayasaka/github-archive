# typed: strict
# frozen_string_literal: true

class Azure::OauthCallbacksController < Azure::BaseController
  include Billing::AzureOauthStateManagement

  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    code = params[:code]
    error = params[:error]
    state = params[:state]

    if error.present?
      flash[:error] = "Authentication with Azure failed. (#{error})"
      redirect_back(fallback_location: "/")
      return
    elsif state.blank?
      flash[:error] = "Missing state from Azure"
      redirect_back(fallback_location: "/")
      return
    end

    begin
      state_hash = state_to_hash(state: state, validate: false)
    rescue JSON::JSONError
      flash[:error] = "Failed decoding state from Azure"
      redirect_back(fallback_location: "/")
      return
    rescue Billing::AzureOauthStateManagement::AzureStateValidationError
      flash[:error] = "Authentication request invalid or expired. Please try again."
      redirect_back(fallback_location: "/")
      return
    end

    org_login = state_hash[:org_login]
    state_hash[:oauth_code] = code
    state = hash_to_state(hash: state_hash)
    params = {
      account_type: "organization",
      account_id: org_login,
      azure_state: state
    }

    redirect_to azure_authentications_path(**params)
  end

  private

  sig { returns(Symbol) }
  def target_for_conditional_access
    # CAP not required. This only redirects to an auth path
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
