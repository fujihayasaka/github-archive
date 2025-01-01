# typed: strict
# frozen_string_literal: true

class Azure::OauthCallbacksController < Azure::BaseController
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

    if error.present?
      flash[:error] = "Authentication with Azure failed. (#{error})"
      redirect_back(fallback_location: "/")
      return
    end

    begin
      state_hash = state_to_hash(state: params[:state])
    rescue JSON::JSONError
      flash[:error] = "Failed decoding state from Azure"
      redirect_back(fallback_location: "/")
      return
    end

    org_login = state_hash[:org_login]

    explicit_tenant_selected = state_hash[:explicit_tenant_selected] || false

    redirect_to azure_authentications_path(
                  account_type: "organization",
                  account_id: org_login,
                  oauth_code: code,
                  explicit_tenant_selected: explicit_tenant_selected
                )
  end

  private

  sig { returns(Symbol) }
  def target_for_conditional_access
    # CAP not required. This only redirects to an auth path
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
