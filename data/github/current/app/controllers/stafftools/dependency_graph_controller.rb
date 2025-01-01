# typed: true
# frozen_string_literal: true

class Stafftools::DependencyGraphController < StafftoolsController

  before_action :ghe_block_pages, except: [:show, :clear_org_dependencies, :redetect_org_dependencies]

  before_action :ensure_org_not_user, only: [:show, :clear_org_dependencies, :redetect_org_dependencies]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index],
    optional: true

  BATCH_SIZE = 100

  def index
    render "stafftools/dependency_graph/index"
  end

  def package_results # rubocop:todo GitHub/UseRestfulActions
    query_all = params[:query_all].eql?("true")

    begin
      packages = if query_all
        Platform::Loaders::Dependencies.load_packages(package_filter: variables).sync.value!
      else
        Platform::Loaders::Dependencies.load_unmapped_packages(package_filter: variables).sync.value!
      end
    rescue DependencyGraph::Client::TimeoutError
      flash[:error] = "Dependency Graph is taking too long to respond, try again later..."
      redirect_to(action: :index)
      return
    end

    render "stafftools/dependency_graph/packages", locals: { packages: packages, query_all: query_all, query_name: params[:query_name], query_manager: params[:query_manager] }
  end

  def assign_package # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.dependency_graph_enabled?

    if target = Repository.with_name_with_owner(params[:target_repository])
      result = DependencyGraph::ReassignPackageMutation.new(
        package_manager: params[:package_manager],
        package_name: params[:package_name],
        repository_id: target.id,
      ).execute
      if result.ok?
        flash[:notice] = "Package #{params[:package_name]} has been assigned to #{params[:target_repository]}"
      else
        flash[:error] = "Unable to reassign #{params[:package_name]} to #{params[:target_repository]} (#{result.error.message})"
      end
    else
      flash[:error] = "Repository #{params[:target_repository]} does not exist"
    end

    redirect_to :back
  end

  def show
    render "stafftools/dependency_graph/show",
      layout: "layouts/stafftools/organization/content",
      locals: {
        owner: this_user,
      }
  end

  def clear_org_dependencies # rubocop:todo GitHub/UseRestfulActions
    DependencyGraphManageOwnerDependenciesJob.perform_later(
      this_user.id,
      task: :clear,
      actor_id: current_user.id,
      trigger: :RESET_TRIGGER_STAFFTOOLS,
    )

    flash[:notice] = "Clear dependencies job enqueued for #{this_user.name}"
    redirect_to org_stafftools_dependency_graph_path(this_user)
  end

  def redetect_org_dependencies # rubocop:todo GitHub/UseRestfulActions
    DependencyGraphManageOwnerDependenciesJob.perform_later(
      this_user.id,
      task: :redetect,
      actor_id: current_user.id,
      trigger: :RESET_TRIGGER_STAFFTOOLS,
    )

    flash[:notice] = "Redetect dependencies job enqueued for #{this_user.name}"
    redirect_to org_stafftools_dependency_graph_path(this_user)
  end

  private

  def variables
    variables = {
      names: params[:query_name],
      package_manager: params[:query_manager],
      first: 100,
    }

    variables.reject! { |_k, v| v.blank? }
    variables
  end

  # Since GHES doesn't currently support storing Packages locally,
  # we'd like to hide this page from users in order to prevent confusion.
  def ghe_block_pages
    render_404 and return if GitHub.enterprise?
  end
end
