# typed: true
# frozen_string_literal: true

class Stafftools::OauthTokensController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_oauth_access_exists, except: [:index]

  layout "layouts/stafftools/user/security", except: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    if this_user.organization?
      render "stafftools/oauth_tokens/org_settings", locals: { organization: this_user }, layout: "layouts/stafftools/organization/security"
    else
      render "stafftools/oauth_tokens/index", layout: "layouts/stafftools/user/security"
    end
  end

  def show
    render "stafftools/oauth_tokens/show"
  end

  def destroy
    OauthAccessTokens.domain.destroy(oauth_access.id, :site_admin, entry_point: :stafftools_oauth_tokens_controller_destroy)

    flash[:notice] = "OAuth token '#{oauth_access.token_last_eight}' revoked"
    redirect_to stafftools_user_oauth_tokens_path(this_user)
  end

  def compare # rubocop:todo GitHub/UseRestfulActions
    hashed_input = OauthAccessTokens::Domain.hash_token(params[:compromized_token])
    if oauth_access.hashed_token == hashed_input
      flash[:notice] = "Compromized token matched, you should revoke this token."
    else
      flash[:notice] = "Token does not match"
    end
    redirect_to :back
  end

  private

  def oauth_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @access ||= OauthAccessTokens.domain.by_id(params[:id].to_i, strict: true)
  end

  def ensure_oauth_access_exists
    render_404 unless oauth_access
  end

end
