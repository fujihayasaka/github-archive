# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::ConcurrencyGroupsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index, :show]

  def index
    return render_404 unless GitHub.actions_enabled?

    @error = nil
    @groups = []
    @next_cursor = nil
    @total_count = 0

    begin
      cursor = params[:cursor]
      limit = (params[:limit] || 50).to_i.clamp(1, 100)

      result = run_service_client.list_concurrency_groups(
        repository_global_id: current_repository.next_global_id,
        cursor: cursor,
        limit: limit
      )

      if result.call_succeeded?
        @groups = result.value.groups
        @next_cursor = result.value.next_cursor.presence
        @total_count = result.value.total_count
      else
        @error = result.options[:message] || "Request failed with status #{result.status}"
      end
    rescue => e
      @error = e.message
    end

    render "stafftools/repositories/actions/concurrency_groups",
      locals: {
        current_repository:,
        groups: @groups,
        next_cursor: @next_cursor,
        total_count: @total_count,
        error: @error
      }
  end

  def show
    return render_404 unless GitHub.actions_enabled?

    group_name = params[:group_name]
    return render_404 if group_name.blank?

    @error = nil
    @group_status = nil

    begin
      result = run_service_client.get_concurrency_group(
        repository_global_id: current_repository.next_global_id,
        group_name: group_name
      )

      if result.call_succeeded?
        @group_status = result.value
      else
        @error = result.options[:message] || "Request failed with status #{result.status}"
      end
    rescue => e
      @error = e.message
    end

    check_suite_ids_by_instance = build_check_suite_lookup(@group_status)

    render "stafftools/repositories/actions/concurrency_group",
      locals: {
        current_repository:,
        group_name: group_name,
        group_status: @group_status,
        check_suite_ids_by_instance: check_suite_ids_by_instance,
        error: @error
      }
  end

  private

  def run_service_client
    use_lab_run_service? ? run_service_lab_client : run_service_production_client
  end

  memoize def run_service_production_client
    base_url = GitHub.actions_run_service_address
    if base_url.blank?
      raise "No run-service URL configured. Set ACTIONS_RUN_SERVICE_URL environment variable."
    end
    ActionsRunService::Twirp::RunServiceClient.new(base_url: base_url)
  end

  memoize def run_service_lab_client
    base_url = GitHub.actions_run_service_lab_address
    if base_url.blank?
      raise "No lab run-service URL configured. Set ACTIONS_RUN_SERVICE_LAB_URL environment variable."
    end
    ActionsRunService::Twirp::RunServiceLabClient.new(base_url: base_url)
  end

  # Check if user requested lab run-service
  def use_lab_run_service?
    params[:use_lab] == "true"
  end

  helper_method :use_lab_run_service?

  # Batch-load check_suite_ids for all instance_ids in a concurrency group.
  # Returns a Hash mapping instance_id => check_suite_id.
  def build_check_suite_lookup(group_status)
    return {} if group_status.nil?

    instances = [group_status.acquired_instance, *group_status.waiting_instances]
    id_to_ext = instances
      .filter_map { |i| [i.instance_id, i.instance_id.split(".").first] if i&.instance_id.present? }
      .to_h

    return {} if id_to_ext.empty?

    ext_to_suite = current_repository.actions_check_suites
      .where(external_id: id_to_ext.values.uniq)
      .to_h { |cs| [cs.external_id, cs.id] }

    id_to_ext.transform_values { |ext_id| ext_to_suite[ext_id] }
  end
end
