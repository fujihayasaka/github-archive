# typed: true
# frozen_string_literal: true

class Api::Admin::Tokens < Api::Admin

  before do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?
  end

  # Get all tokens
  # rubocop:todo GitHub/ControlAccess
  get "/admin/tokens", operation_id: "enterprise-admin/list-personal-access-tokens" do
    scope = OauthAccess.personal_tokens.order(:accessed_at).preload(:application, :authorization, :user)
    tokens = paginate_rel(scope)

    deliver :oauth_access_hash, tokens, detail: true, user: true
  end
  # rubocop:enable GitHub/ControlAccess

  # Delete a token
  # rubocop:todo GitHub/ControlAccess
  delete "/admin/tokens/:token_id", operation_id: "enterprise-admin/delete-personal-access-token" do
    token_id = int_id_param!(key: :token_id)
    token = record_or_404(OauthAccessTokens.domain.by_id(token_id))

    if token.id == current_user&.oauth_access&.id
      deliver_error!(403, message: "Cannot delete token being used to access this API.")
    end

    OauthAccessTokens.domain.destroy(token.id, :site_admin, entry_point: :rest_api_admin_tokens_delete_token)

    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess
end
