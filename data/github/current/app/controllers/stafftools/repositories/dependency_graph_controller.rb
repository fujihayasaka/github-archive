# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::DependencyGraphController < StafftoolsController
  include Repositories::Domain::Provider

  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:dependency_graph, :exclude_dependency_snapshot, :download_dependency_snapshot]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:dependency_graph], optional: true

  def dependency_graph # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.dependency_graph_enabled?

    result = T.let(nil, T.untyped)
    packages = []
    dependents_unavailable = true
    timing = 0.0

    if current_repository.public?
      timing = Benchmark.measure do
        result = Platform::Loaders::Dependencies.load_packages({
          package_filter: {
            repository_id: current_repository.id,
            first: 30,
            preview: current_repository.dependency_graph_preview?,
            debug: true,
          },
          include_dependent_counts: true,
        }).sync
      end

      dependents_unavailable = !result.ok?
      packages = result.value { [] }
    end

    manifest_paths = DependencyGraph::ManifestsQuery.new(
        manifest_filter: { repository_id: current_repository.id }
      ).results.value![:manifests].map(&:filename)

    snapshots_or_error = get_canonical_snapshots_or_error

    respond_to do |format|
      format.html do
        render "stafftools/repositories/dependency_graph", locals: {
          timing: timing,
          packages: packages,
          current_repo: current_repository,
          dependents_unavailable: dependents_unavailable,
          manifest_paths: manifest_paths,
          snapshots_or_error: snapshots_or_error,
        }
      end
    end
  end

  def get_canonical_snapshots_or_error # rubocop:todo GitHub/UseRestfulActions
    p = DependencySnapshot::DependencySnapshotProvider.new
    resp = p.get_included_dependency_snapshots(repository: current_repository)
    if resp[:status_code] != 200
      return "Error #{resp[:status_code]}: #{resp[:error]}"
    end
    resp[:response].to_h[:included_snapshots]
  end

  def exclude_canonical_snapshots(ids) # rubocop:todo GitHub/UseRestfulActions
    p = DependencySnapshot::DependencySnapshotProvider.new
    resp = p.exclude_dependency_snapshots(repository: current_repository, snapshot_ids: ids)
    if resp[:status_code] != 200
      "Error #{resp[:status_code]}: #{resp[:error]}"
    else
      "Success"
    end
  end

  def detect_manifests # rubocop:todo GitHub/UseRestfulActions
    RepositoryDependencyRedetectJob.perform_later(
      current_repository.id,
      actor_id: current_user.id,
      trigger: :RESET_TRIGGER_STAFFTOOLS
    )

    flash[:notice] = "Manifest detection job enqueued"
    redirect_to gh_dependency_graph_stafftools_repository_path(current_repository)
  end

  def clear_dependencies # rubocop:todo GitHub/UseRestfulActions
    # no DS-API static manifest treatment yet; use clear-canonicals chatop for now
    RepositoryDependencyClearDependencies.perform_later(
      current_repository.id,
      actor_id: current_user.id,
      trigger: :RESET_TRIGGER_STAFFTOOLS,
    )

    flash[:notice] = "Clear dependencies job enqueued"
    redirect_to gh_dependency_graph_stafftools_repository_path(current_repository)
  end

  def download_dependency_snapshot # rubocop:todo GitHub/UseRestfulActions
    id = params.require(:snapshot_id).to_i

    p = DependencySnapshot::DependencySnapshotProvider.new
    resp = p.get_dependency_snapshot(repository: current_repository, snapshot_id: id)
    contents = resp[:response].payload
    send_data contents, filename: "dependency_snapshot_#{id}.txt", disposition: "attachment", status: 200
  end

  def exclude_dependency_snapshot # rubocop:todo GitHub/UseRestfulActions
    id = params.require(:snapshot_id).to_i
    result = exclude_canonical_snapshots([id])
    flash[:notice] = result
    redirect_to gh_dependency_graph_stafftools_repository_path(current_repository)
  end

  def clear_snapshot_dependencies # rubocop:todo GitHub/UseRestfulActions
    snapshots_or_error = get_canonical_snapshots_or_error
    if snapshots_or_error.is_a?(String)
      flash[:notice] = "Error: #{snapshots_or_error}"
    else
      ids = snapshots_or_error.map { |s| s[:snapshot_id] }
      result = exclude_canonical_snapshots(ids)
      flash[:notice] = result
    end
    redirect_to gh_dependency_graph_stafftools_repository_path(current_repository)
  end

  # Set the Used By repository configuration flag.
  def set_used_by # rubocop:todo GitHub/UseRestfulActions
    if params[:used_by_enabled] == "1"
      flash[:notice] = "Used By is now enabled" if current_repository.enable_used_by(actor: current_user)
    elsif params[:used_by_enabled] == "0"
      flash[:notice] = "Used By is now disabled" if current_repository.disable_used_by(actor: current_user)
    end

    redirect_to :back
  end
end
