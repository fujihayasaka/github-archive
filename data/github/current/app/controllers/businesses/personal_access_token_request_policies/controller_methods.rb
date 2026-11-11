# typed: strict
# frozen_string_literal: true

module Businesses::PersonalAccessTokenRequestPolicies::ControllerMethods
  sig { params(business: Business, actor: User, params: ActionController::Parameters).returns([Symbol, String]) }
  def set_pat_request_auto_approvals_configuration(business, actor, params)
    case params[:pat_auto_approvals]
    when "enable"
      business.enable_auto_pat_request_approval(actor: actor)
      [:notice, "Fine-grained personal access tokens that target organizations in your enterprise will not require approval. Organization administrators cannot override this setting."]
    when "disable"
      business.disable_auto_pat_request_approval(actor: actor)
      [:notice, "All organizations will require review and approval of member requests for fine-grained personal access tokens that target that organization."]
    when "reset"
      business.reset_auto_pat_request_approval(actor: actor)
      [:notice, "All organizations can now choose whether to require administrator approval of fine-grained personal access tokens. By default, approval is required."]
    else
      [:error, "Unknown option provided."]
    end
  end
end
