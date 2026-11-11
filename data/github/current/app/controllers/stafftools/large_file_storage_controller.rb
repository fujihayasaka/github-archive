# typed: true
# frozen_string_literal: true

class Stafftools::LargeFileStorageController < StafftoolsController
  include Stafftools::TradeCompliance::SharedControllerMethods
  include ActionView::Helpers::NumberHelper
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :ensure_user_exists, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    network_ids = ::Media::Blob.possible_lfs_network_ids(this_user)
    lfs_disk_usage = ::Media::Blob.network_lfs_disk_usage(network_ids)
    lfs_repos = ::Media::Blob.lfs_repositories_for_owner(this_user).includes(:network).paginate(page: params[:page])
    lfs_networks = Platform::Loaders::LfsNetworksByUsage.load(this_user.id).sync

    view = Stafftools::LargeFileStorageView.new(account: this_user, lfs_repos: lfs_repos, lfs_disk_usage: lfs_disk_usage, lfs_networks: lfs_networks, user: this_user)

    case this_user.site_admin_context
    when "organization"
      render "stafftools/large_file_storage/show", layout: "layouts/stafftools/organization/content", locals: {
        view: view
      }
    when "user"
      render "stafftools/large_file_storage/show", layout: "layouts/stafftools/user/content", locals: {
        view: view
      }
    else
      render_404
    end
  end
end
