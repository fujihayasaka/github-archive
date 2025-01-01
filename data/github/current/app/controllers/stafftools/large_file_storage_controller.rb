# typed: true
# frozen_string_literal: true

class Stafftools::LargeFileStorageController < StafftoolsController
  include Stafftools::TradeCompliance::SharedControllerMethods
  include ActionView::Helpers::NumberHelper
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :ensure_user_exists, only: [:show, :edit, :update]
  before_action only: :update do
    T.bind(self, Stafftools::LargeFileStorageController)

    ensure_target_not_restricted(feature_type: :cost_management)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

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
    only: [:edit, :index, :show], optional: true

  def index
    sort = params[:sort]
    sort = "bandwidth_down" unless %w(storage bandwidth_down bandwidth_up).include?(sort)

    @statuses = Asset::Status.
      where("asset_type = 0 AND (storage > 0 OR bandwidth_down > 0)").
      order("#{sort} desc").
      includes(:owner).
      limit(30).
      page(current_page)

    render "stafftools/large_file_storage/index"
  end

  def show
    network_ids = ::Media::Blob.possible_lfs_network_ids(this_user)
    lfs_disk_usage = ::Media::Blob.network_lfs_disk_usage(network_ids)
    lfs_repos = ::Media::Blob.lfs_repositories_for_owner(this_user).includes(:network).paginate(page: params[:page])
    lfs_networks = Platform::Loaders::LfsNetworksByUsage.load(this_user.id).sync
    variables = { id: this_user.global_relay_id }.merge(graphql_pagination_params(page_size: 35))

    actor_statuses = Asset::ActorStatus.lfs.
      where(owner_id: this_user.id).
      includes([:actor, :owner]).
      order("bandwidth_down desc").
      limit(30).
      page(current_page)

    view = Stafftools::LargeFileStorageView.new(account: this_user, actor_statuses: actor_statuses, lfs_repos: lfs_repos, lfs_disk_usage: lfs_disk_usage, lfs_networks: lfs_networks, user: this_user)

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

  def edit
    return render_404 unless subscription_data_packs_can_be_changed?(this_user)

    total_packs = (params[:packs] || this_user.data_packs).to_i
    @data_pack_change = ::Billing::PlanChange::DataPackChange.new(this_user,
      total_packs: total_packs)

    respond_to do |format|
      format.json do
        render json: {
          url: stafftools_user_edit_large_file_storage_path(this_user, packs: total_packs),
          selectors: {
            ".unstyled-total-data-packs"       => @data_pack_change.total_packs,
            ".unstyled-total-data-packs-label" => "data pack".pluralize(@data_pack_change.total_packs),
            ".unstyled-total-price"             => @data_pack_change.total_price.format(sign_before_symbol: true),
            ".unstyled-renewal-price"           => @data_pack_change.renewal_price.format,
            ".unstyled-pack-storage-total"      => number_with_delimiter(@data_pack_change.storage_quota.round),
            ".unstyled-pack-bandwidth-total"    => number_with_delimiter(@data_pack_change.bandwidth_quota.round),
          },
        }
      end

      format.html do
        render "stafftools/large_file_storage/edit", layout: "stafftools/user/billing"
      end
    end
  end

  def update
    return render_404 unless subscription_data_packs_can_be_changed?(this_user)

    total_packs = params[:asset_status] && params[:asset_status][:total_packs]
    total_packs ||= this_user.data_packs
    asset_status = this_user.asset_status || this_user.build_asset_status

    asset_status.update_data_packs(quantity: total_packs.to_i, actor: current_user)

    flash[:notice] = "Successfully updated data plan."
    redirect_to billing_stafftools_user_path(this_user)
  end
end
