# typed: true
# frozen_string_literal: true

class Stafftools::GpgKeysController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_gpg_key_exists, only: [:show, :database]

  layout "layouts/stafftools/user/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:database]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
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
    only: [:database, :show, :index],
    optional: true

  def index
    query = "user_id:#{this_user.id} AND action:gpg_key.*"
    if GitHub.driftwood_ade_queries_enabled?
      query = "webevents | where user_id == #{this_user.id} and action startswith 'gpg_key'"
    end
    fetch_audit_log_teaser(query)
    render "stafftools/gpg_keys/index"
  end

  def show
    key = this_key.subkey? ? this_key.primary_key : this_key
    query = "data.key_id:#{key.hex_key_id}"
    if GitHub.driftwood_ade_queries_enabled?
      query = "webevents | where data.key_id == '#{key.hex_key_id}'"
    end
    fetch_audit_log_teaser(query)
    render "stafftools/gpg_keys/show"
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/gpg_keys/database"
  end

  private

  def this_key
    @this_key = this_user.gpg_keys.find(params[:id])
  end
  helper_method :this_key

  def ensure_gpg_key_exists
    render_404 if this_key.nil?
  end

end
