# typed: true
# frozen_string_literal: true

class Stafftools::OauthTokensController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_oauth_access_exists, except: [:index]

  layout "layouts/stafftools/user/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
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
    render "stafftools/oauth_tokens/index"
  end

  def show
    render "stafftools/oauth_tokens/show"
  end

  def destroy
    oauth_access.destroy_with_explanation(:site_admin, entry_point: :stafftools_oauth_tokens_controller_destroy)

    flash[:notice] = "OAuth token '#{oauth_access.token_last_eight}' revoked"
    redirect_to stafftools_user_oauth_tokens_path(this_user)
  end

  def compare # rubocop:todo GitHub/UseRestfulActions
    hashed_input = OauthAccess.hash_token(params[:compromized_token])
    if oauth_access.hashed_token == hashed_input
      flash[:notice] = "Compromized token matched, you should revoke this token."
    else
      flash[:notice] = "Token does not match"
    end
    redirect_to :back
  end

  private

  def oauth_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @access ||= this_user.oauth_accesses.find(params[:id])
  end

  def ensure_oauth_access_exists
    render_404 unless oauth_access
  end

end
