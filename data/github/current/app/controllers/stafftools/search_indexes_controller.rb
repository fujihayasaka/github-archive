# typed: true
# frozen_string_literal: true

class Stafftools::SearchIndexesController < StafftoolsController
  before_action :find_index, except: [:index, :new, :create,
                                         :toggle_code_search,
                                         :toggle_code_search_indexing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

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
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:repair]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :repair],
    optional: true

  def index
    @clusters = ::Search::ClusterStatus.new
    @indices = []

    index_map = ::Elastomer.router.index_map
    index_map.refresh

    index_names.each do |key|
      ary = index_map.fetch(key)
      next if ary.nil?
      ary.each { |settings| @indices << Search::IndexView.new(settings.to_h) }
    end

    @indices = VersionSorter.sort(@indices) { |index| index.name }

    render "stafftools/search_indexes/index"
  end

  def toggle_code_search # rubocop:todo GitHub/UseRestfulActions
    clusters = ::Search::ClusterStatus.new
    if clusters.code_search_enabled?
      instrument("staff.disable_code_search")
      clusters.disable_code_search
    else
      instrument("staff.enable_code_search")
      clusters.enable_code_search
    end

    redirect_to :back
  end

  def toggle_code_search_indexing # rubocop:todo GitHub/UseRestfulActions
    clusters = ::Search::ClusterStatus.new
    if GitHub.code_search_indexing_enabled?
      instrument("staff.disable_code_search_indexing")
      clusters.disable_code_search_indexing
    else
      instrument("staff.enable_code_search_indexing")
      clusters.enable_code_search_indexing
    end

    redirect_to :back
  end

  def new
    @indices = index_names
    @clusters = ::Elastomer.router.available_clusters
    @index = Search::IndexView.new
    render "stafftools/search_indexes/new"
  end

  def create
    if GitHub.enterprise? && search_index_view_params[:kind] == "audit-log"
      return render_404
    end

    index = Search::IndexView.new(search_index_view_params)
    index.create
    instrument("staff.create_new_index")
    redirect_to stafftools_search_index_path(index.name)
  end

  def show
    @repair_job = @index.repair_job
    @kind_has_multiple_primaries = kind_has_multiple_primaries(@index.name)
    render "stafftools/search_indexes/show"
  end

  def update
    @index.update
    instrument("staff.update_index")
    redirect_to :back
  end

  def destroy
    if @index.primary
      flash[:error] = "The primary index cannot be deleted."
      redirect_to :back
    else
      @index.destroy
      instrument("staff.destroy_primary_index")
      redirect_to stafftools_search_indexes_path
    end
  end

  def make_primary # rubocop:todo GitHub/UseRestfulActions
    @index.make_primary
    redirect_to :back
  end

  def update_version # rubocop:todo GitHub/UseRestfulActions
    old_version = @index.version
    @index.update_version
    instrument("staff.update_elasticsearch_mapping_version", old_version: old_version, new_version: @index.version, index_name: @index.name)
    flash[:notice] = "Mapping version updated"

    GitHub.dogstats.event \
        "Mapping version updated for: #{@index.name.inspect}",
        "Mapping version updated for #{@index.name.inspect} from #{old_version.inspect} to #{@index.version.inspect} from stafftools",
        tags: %W[search:ops action:update-version from:stafftools]

    redirect_to :back
  end

  def update_mapping # rubocop:todo GitHub/UseRestfulActions
    begin
      if @index.mapping_diff.changes?
        old_version = @index.version
        @index.update_mapping
        new_version = @index.version
        instrument("staff.update_elasticsearch_mapping", old_version:, new_version:, index_name: @index.name)
        flash[:notice] = "Mapping updated"
      else
        flash[:notice] = "No changes detected in mapping"
      end
    rescue ElastomerClient::Client::IllegalArgument,
      Elastomer::Mappings::UpdatesNotSupportedError,
      Elastomer::Mappings::DestructiveMappingChangeError => e
      flash[:error] = e.message
    end

    redirect_back(fallback_location: stafftools_search_index_path(@index.name))
  end

  def repair # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        if repair_job = @index.repair_job
          render repair_job # rubocop:disable GitHub/RailsControllerRenderLiteral
        else
          head 404
        end
      end
    end
  end

  def start_repair # rubocop:todo GitHub/UseRestfulActions
    if current_user.feature_enabled?(:native_reindex)
      repair_type = params[:repair_type] || "index_repair"

      case repair_type
      when "index_repair"
        if repair_job = @index.repair_job
          if repair_job.is_a?(RepairMemexProjectItemsIndexJob)
            begin
              repair_memex_projects_visited_after(repair_job)
            rescue ArgumentError
              flash[:error] = "Invalid visited_after time"
              redirect_to :back
              return
            end
          end

          workers_count = Integer(params[:workers].presence || 1)
          repair_job.enable
          repair_job.start workers_count

          GitHub.dogstats.event \
            "Repair started for: #{@index.name.inspect}",
            "Repair has been started for #{@index.name.inspect} with #{workers_count} workers from stafftools",
            tags: %W[search:ops action:repair-start from:stafftools]
        end
      when "native_reindex"
        if @index.primary
          flash[:error] = "Reindex Job CANNOT be on a primary index. Please choose a non-primary index or create one."
          redirect_to :back
          return
        end

        @index.reindex_job.start

        GitHub.dogstats.event \
          "Native Reindex started for: #{@index.name.inspect}",
          "Native Reindex has been started for #{@index.name.inspect}",
          tags: %W[search:ops action:repair-start from:stafftools]
      end
    else
      if repair_job = @index.repair_job
        if repair_job.is_a?(RepairMemexProjectItemsIndexJob)
          begin
            repair_memex_projects_visited_after(repair_job)
          rescue ArgumentError
            flash[:error] = "Invalid visited_after time"
            redirect_to :back
            return
          end
        end

        workers_count = Integer(params[:workers].presence || 1)
        repair_job.enable
        repair_job.start workers_count

        GitHub.dogstats.event \
          "Repair started for: #{@index.name.inspect}",
          "Repair has been started for #{@index.name.inspect} with #{workers_count} workers from stafftools",
          tags: %W[search:ops action:repair-start from:stafftools]
      end
    end

    redirect_to :back
  end

  def update_workers # rubocop:todo GitHub/UseRestfulActions
    if repair_job = @index.repair_job
      workers_count = params[:worker_count].blank? ? 1 : Integer(params[:worker_count])
      repair_job.enable.start workers_count
      flash[:notice] = "Set repair jobs to #{workers_count}"

      GitHub.dogstats.event \
      "Worker count updated for: #{@index.name.inspect}",
      "Worker count updated for #{@index.name.inspect} with #{workers_count} workers from stafftools",
      tags: %W[search:ops action:repair-update from:stafftools]
    end

    redirect_to :back
  end

  def pause_repair # rubocop:todo GitHub/UseRestfulActions
    if repair_job = @index.repair_job
      repair_job.pause

      GitHub.dogstats.event \
        "Repair stopped for: #{@index.name.inspect}",
        "Repair has been stopped for #{@index.name.inspect} from stafftools",
        tags: %W[search:ops action:repair-stop from:stafftools]
    end

    redirect_to :back
  end

  def update_reindex_job # rubocop:todo GitHub/UseRestfulActions
    if reindex_job = @index.reindex_job
      request_per_second = params[:request_per_second].blank? ? -1 : Integer(params[:request_per_second]) rescue 0

      unless request_per_second > 0 || request_per_second == -1
        flash[:error] = "Requests Per Second needs to be an integer greater than 0 or set to -1 to disable throttling."
        redirect_to :back
        return
      end

      reindex_job.rethrottle(request_per_second)

      flash[:notice] = request_per_second == -1 ? "Reindex job throttling is disabled" : "Reindex job is set to #{request_per_second} Requests Per Second"

      GitHub.dogstats.event \
      "Reindex Rate Per Second updated for: #{@index.name.inspect}",
      "Reindex Rate Per Second updated for #{@index.name.inspect} with #{request_per_second} workers from stafftools",
      tags: %W[search:ops action:repair-update from:stafftools]
    end

    redirect_to :back
  end

  def reset_repair # rubocop:todo GitHub/UseRestfulActions
    if repair_job = @index.repair_job
      repair_job.reset!

      GitHub.dogstats.event \
        "Repair reset for: #{@index.name.inspect}",
        "Repair has been reset for #{@index.name.inspect} from stafftools",
        tags: %W[search:ops action:repair-reset from:stafftools]
    end

    if reindex_job = @index.reindex_job
      reindex_job.cancel
      reindex_job.reset!

      GitHub.dogstats.event \
      "Reindex reset for: #{@index.name.inspect}",
      "Reindex has been reset for #{@index.name.inspect} from stafftools",
      tags: %W[search:ops action:repair-reset from:stafftools]
    end

    redirect_to :back
  end

  private

  def find_index
    if GitHub.enterprise?
      return render_404 if params[:id].include?("audit_log")
    end
    return render_404 if ::Elastomer.router.get_index_config(params[:id]).nil?
    view_params = params[:search_index_view].nil? ? { name: params[:id] } : search_index_view_params
    @index = Search::IndexView.new(view_params)
  end

  def kind_has_multiple_primaries(name)
    kind = Elastomer.env.lookup_index(name).logical_index_name
    primaries = Elastomer.router.index_map.primaries(kind)
    primaries.size > 1
  end

  def index_names
    excluded_index_names = %w[audit_log]
    if GitHub.enterprise?
      excluded_index_names += %w[blog marketplace-listings non-marketplace-listings repository-actions enterprises]
      excluded_index_names += %w[registry-packages] unless PackageRegistryHelper.ghes_registry_enabled?
      excluded_index_names += %w[showcases] unless GitHub.showcase_enabled?
    end

    ::Elastomer.env.index_names.reject do |index_name|
      excluded_index_names.any? do |excluded_index_name|
        index_name.start_with?(excluded_index_name)
      end
    end
  end

  def search_index_view_params
    params.require(:search_index_view).permit(
      :kind,
      :name,
      :cluster,
      :searchable,
      :writable,
    )
  end

  def repair_memex_projects_visited_after(repair_job)
    return unless repair_job.is_a?(RepairMemexProjectItemsIndexJob)
    return unless (visited_after = params[:visited_after]) && !visited_after.blank?

    repair_job.visited_after = Date.iso8601(visited_after)
  end
end
