# typed: true
# frozen_string_literal: true

class Stafftools::NetworksController < StafftoolsController
  # rubocop:todo GitHub/MapToService
  map_to_service :git_maintenance, only: [:schedule_maintenance_for_failed, :mark_as_broken, :schedule_maintenance]
  # rubocop:enable GitHub/MapToService

  include ActionView::Helpers::TextHelper

  before_action :ensure_repo_exists, except: [
    :index, :schedule_maintenance, :schedule_maintenance_for_failed
  ]

  before_action :ensure_network_health

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:children]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:siblings]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :children, :siblings], optional: true

  NETWORKS_PER_PAGE = 20

  # Do some sanity checks of the network and network family
  # If the network is broken, queue a job to fix it so later requests will succeed
  # The current request will likely 500, but future requests should succeed once the job completes
  def ensure_network_health # rubocop:todo GitHub/UseRestfulActions
    return if current_repository.nil?
    return if current_repository.network.nil?

    if current_repository.network.root.nil?
      # if the current_repository has a network, but no network root, queue the fix job
      RepositorySupportJob.perform_later(network_id: current_repository.network.id)
      return
    end

    begin
      current_repository.network.root_network
    rescue RepositoryNetwork::InvalidNetworkError => e
      # if root_network raises, the network family has a circular reference. Fix it.
      RepositorySupportJob.perform_later(network_id: current_repository.network.id)
    end
  end

  layout :new_nav_layout
  private def new_nav_layout
    if action_name == "index"
      "stafftools"
    else
      "layouts/stafftools/repository/collaboration"
    end
  end

  def index
    @status_names = RepositoryNetwork::Maintenance::MAINTENANCE_STATUSES
    @show_status = params[:maintenance_status] || "failed"
    @networks = RepositoryNetwork
      .where(maintenance_status: @show_status)
      .order("last_maintenance_attempted_at ASC")
      .paginate(page: current_page, per_page: NETWORKS_PER_PAGE)
    render "stafftools/networks/index"
  end

  def schedule_maintenance_for_failed # rubocop:todo GitHub/UseRestfulActions
    networks = RepositoryNetwork
      .where(maintenance_status: "failed")
      .order("last_maintenance_attempted_at ASC")
      .limit(NETWORKS_PER_PAGE)
    networks.each do |network|
      network.schedule_maintenance
    end
    flash[:notice] = "Maintenance scheduled for #{pluralize(networks.size, "failed network")}"
    redirect_to :back
  end

  def show
    render "stafftools/networks/show"
  end

  # View the detailed (and often slow) network tree
  def tree # rubocop:todo GitHub/UseRestfulActions
    @repo_map = current_repository.network.full_network_tree
    render "stafftools/networks/tree"
  end

  def children # rubocop:todo GitHub/UseRestfulActions
    @repos = sort_by_owner_login(current_repository.children.preload(:owner))
    @title = "Children"
    render "stafftools/networks/children"
  end

  def siblings # rubocop:todo GitHub/UseRestfulActions
    @repos = sort_by_owner_login(current_repository.parent.children.preload(:owner))
    @repos -= [current_repository]
    @title = "Siblings"
    render "stafftools/networks/children"
  end

  # Makes this repo the root of its network
  def change_root # rubocop:todo GitHub/UseRestfulActions
    current_repository.make_network_root
    flash[:notice] = "Making repository the root of the network…"
    redirect_to :back
  end

  # Disconnect this repo from its network
  def detach # rubocop:todo GitHub/UseRestfulActions
    orchestration = current_repository.detach!
    url = "/stafftools/repositories/#{current_repository.name_with_display_owner}/repository_orchestrations/#{orchestration&.id}"
    redirect_to url
  end

  # Extract this repo and all forks from its network
  def extract # rubocop:todo GitHub/UseRestfulActions
    orchestration = current_repository.extract!(actor: this_user)
    url = "/stafftools/repositories/#{current_repository.name_with_display_owner}/repository_orchestrations/#{orchestration&.id}"
    redirect_to url
  end

  def sync_org_owned_private_networks_with_forks # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.sync_org_owned_private_network_with_forks
    redirect_to :back
  end

  def block_archive_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.block_archive_resource(actor: this_user)
    redirect_to :back
  end

  def enable_gitop_fail_fast # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.enable_fail_fast(actor: this_user)
    redirect_to :back
  end

  def disable_gitop_fail_fast # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.disable_fail_fast(actor: this_user)
    redirect_to :back
  end

  def unblock_archive_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.unblock_archive_resource(actor: this_user)
    redirect_to :back
  end

  def block_raw_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.block_raw_resource(actor: this_user)
    redirect_to :back
  end

  def unblock_raw_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.unblock_raw_resource(actor: this_user)
    redirect_to :back
  end

  # Reattach this repo and all forks to its parent network
  def reattach # rubocop:todo GitHub/UseRestfulActions
    orchestration = current_repository.reattach!
    url = "/stafftools/repositories/#{current_repository.name_with_display_owner}/repository_orchestrations/#{orchestration&.id}"
    redirect_to url
  end

  def attach_to # rubocop:todo GitHub/UseRestfulActions
    repo_id = params[:attach_to_repo_id]
    dest_repo = if FeatureFlag.vexi.enabled?(:repos_domain_stafftools, default: false)
      Repositories.domain.by_id(repo_id.to_i)
    else
      Repository.find_by(id: repo_id)
    end
    orchestration = current_repository.attach_to!(dest_repo)
    url = "/stafftools/repositories/#{current_repository.name_with_display_owner}/repository_orchestrations/#{orchestration&.id}"
    redirect_to url
  end

  # Change a forked repositories parent to a different repository in the same network
  # When a repository is the root of a network of forks the root will need to be reassigned
  # in order to leave the network in a good state when that repository is reparented.
  def reparent # rubocop:todo GitHub/UseRestfulActions
    new_parent = Repository.nwo(params[:new_parent])

    begin
      current_repository.reparent! new_parent
      nwo = current_repository.name_with_owner
      new_nwo = new_parent.name_with_owner
      flash[:notice] = "#{nwo} is now a child of #{new_nwo}"
    rescue ArgumentError, Repository::NetworkDependency::InvalidAncestryError => e
      flash[:error] = e.message
    end

    redirect_to :back
  end

  # Rebuilds the data used by the network graph
  def rebuild_network_graph # rubocop:todo GitHub/UseRestfulActions
    current_repository.network_graph.force_build
    flash[:notice] = "Network graph rebuild job enqueued"
    redirect_to :back

  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  # Increment the git cache. Useful as a final step after removing sensitive data.
  # see app/models/repository/rpc_dependency for more information
  def increment_git_cache # rubocop:todo GitHub/UseRestfulActions
    current_repository.increment_cache_version!
    flash[:notice] = "Repository Git cache invalidated"
    redirect_to :back
  end

  def schedule_maintenance # rubocop:todo GitHub/UseRestfulActions
    if current_repository
      current_repository.network.schedule_maintenance
      RepositorySupportJob.perform_later(network_id: current_repository.network.id)
      flash[:notice] = "Network maintenance scheduled for network #{current_repository.network.id}"
    else
      flash[:error] = "The root repository of the network no longer exists"
    end
    redirect_to :back
  end

  def mark_as_broken # rubocop:todo GitHub/UseRestfulActions
    current_repository.network.mark_as_broken
    flash[:warn] = "The repository and all its forks have been marked as broken"
    redirect_to :back
  end

  private

  def sort_by_owner_login(repos)
    valid_repos = repos.reject { |r| r.owner.nil? }
    valid_repos.sort_by { |r| r.owner.login }
  end
end
