# typed: true
# frozen_string_literal: true

module Copilot
  class SyncUserEditorsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
    schedule interval: 1.day, condition: -> { GitHub.copilot_enabled? }
    gate_with_feature_flag :populate_user_editor_data
    exempt_from_tenant_context_requirement

    DEFAULT_BATCH_SIZE = 1000
    DEFAULT_SLEEP_SECONDS = 0.5
    REDIS_PIPELINE_BATCH_SIZE = 100

    EDITOR_MAP = {
      "vscode" => "vscode",
      "visual studio code" => "vscode",
      "vs code" => "vscode",
      "code" => "vscode",
      "visualstudio" => "visual_studio",
      "visual studio" => "visual_studio",
      "jetbrains" => "jetbrains",
      "intellij" => "jetbrains",
      "pycharm" => "jetbrains",
      "webstorm" => "jetbrains",
      "goland" => "jetbrains",
      "rider" => "jetbrains",
      "neovim" => "neovim",
      "nvim" => "neovim",
      "azure data studio" => "azure_data_studio",
      "azuredatastudio" => "azure_data_studio",
      "studio" => "azure_data_studio"
    }

    CANONICAL_EDITORS = %w[
      vscode
      visual_studio
      jetbrains
      neovim
      azure_data_studio
    ]

    DOGSTATS_PREFIX = "copilot.sync_user_editors"

    def perform(batch_size: DEFAULT_BATCH_SIZE, dry_run: false, num_of_batches: nil, sleep_duration: DEFAULT_SLEEP_SECONDS, after_id: nil)
      kusto_client = Copilot::ActivityKustoClientProvider.kusto_client
      @dry_run = dry_run
      @batch_size = batch_size

      begin
        @redis = Copilot.activity_redis
      rescue Redis::BaseConnectionError => redis_conn_err
        GitHub.logger.error("Redis connection failed: #{redis_conn_err.message}")
        return
      end

      total_limit = num_of_batches ? @batch_size * num_of_batches : nil

      # Since we process users in descending order, we can limit
      # the query to those with ids < the after_id if provided.
      user_scope = Copilot::LimitedUser
      if after_id.present?
        user_scope = user_scope.where("id < ?", after_id)
        dry_run_output "Limiting users to those with id < #{after_id}"
      end

      if total_limit
        user_scope = user_scope.limit(total_limit)
      end
      user_scope.find_in_batches(batch_size: @batch_size, order: :desc).each_with_index do |batch, idx|
        batch_array = batch.to_a
        last_limited_user_id = T.must(batch_array.last&.id)
        batch_user_ids = T.must(batch_array.pluck(:user_id))
        existing_usage_data = get_existing_usage_data(batch_user_ids)

        # NOTE: since at this time we only have deep links for vscode (and extremely little azure data studio data)
        # I think it's in our best interest to reduce unnecessary kusto queries by checking first if we already
        # have vscode usage for the user. If we do, we can skip queries for those. If we decide we need more info
        # in the future, we can modify this pruning.
        ids_to_query = if FeatureFlag.vexi.enabled?(:copilot_ide_query_pruning, default: false)
          prune_known_vscode_user_ids(batch_user_ids, existing_usage_data)
        else
          batch_user_ids
        end

        next if ids_to_query.empty?

        query = <<~KQL
          copilot_unified_engagement
          | where isnotempty(editor)
          | where user_dotcom_id in (#{ids_to_query.join(",")})
          | project user_dotcom_id, editor
          | summarize editors = make_set(editor) by user_dotcom_id
        KQL

        result = T.let(nil, T.nilable(Kusto::Data::Dataset))
        begin
          result = GitHub.dogstats.distribution_time("#{DOGSTATS_PREFIX}.kusto_query", tags: stats_tags) do
            kusto_client.query("copilot", query)
          end
        rescue Kusto::Error => e
          GitHub.logger.error(
            "Kusto query failed",
            {
              "exception" => e,
              "details" => e.details,
              "batch_index" => idx,
              "code.namespace" => self.class.name,
              "code.function" => __method__
            }
          )
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.kusto_query.error", tags: stats_tags)
          next
        end

        GitHub.dogstats.count("#{DOGSTATS_PREFIX}.kusto_query.rows_returned", result.primary_result_table.rows.size, tags: stats_tags)

        if result.primary_result_table.rows.empty?
          GitHub.logger.info("No data returned for batch #{idx}")
          next
        end

        columns = result.primary_result_table.columns.map(&:name)
        user_checklists_to_update = []

        result.primary_result_table.rows.each do |row|
          row_hash = Hash[columns.zip(row)]
          user_id = row_hash["user_dotcom_id"].to_i
          editors = row_hash["editors"]

          unless editors.is_a?(Array)
            GitHub.logger.warn("Unexpected data format for editors: #{editors.inspect}")
            next
          end

          mapped_editors = editors.map { |e| EDITOR_MAP[e.to_s.downcase.strip] }.compact.uniq
          next if mapped_editors.empty?

          existing_editors = existing_usage_data[user_id]
          if existing_editors.present?
            same = existing_editors.to_set == mapped_editors.to_set
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.redis.hit", tags: stats_tags(["changed:#{!same}"]))
            if same
              dry_run_output "No change for user #{user_id}: #{mapped_editors}"
              next
            end
          else
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.redis.miss", tags: stats_tags)
          end

          if @dry_run
            dry_run_output "Would write to Redis for user #{user_id}: #{mapped_editors}"
          else
            set_editors(user_id, mapped_editors)
          end
          user_checklists_to_update << user_id
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.redis.processed_users", tags: stats_tags(["status:success"]))
        end

        complete_checklist_step_one(user_checklists_to_update)
        GitHub.logger.info("Processed batch ##{idx} of users", { "batch_size" => ids_to_query.size, "last_limited_user_id" => last_limited_user_id })

        if idx + 1 == num_of_batches
          GitHub.logger.info("Reached the specified number of batches: #{num_of_batches}")
          return
        end

        sleep(sleep_duration)
      end
    end

    private

    # This method updates the copilot_free_user_checklist for each limited user.
    # If we detect users have used an IDE before, we automatically mark the first step as completed
    def complete_checklist_step_one(user_ids)
      checklist = :copilot_free_user_checklist
      ::User.where(id: user_ids).find_each(batch_size: @batch_size)  do |user|
        current_setting = JSON.parse(user.settings.get(checklist))
        next unless current_setting.is_a?(Array) && current_setting[0] == false

        updated_setting = current_setting.dup
        updated_setting[0] = true

        if @dry_run
          dry_run_output "Would update #{checklist} for user #{user.id}: #{updated_setting}"
        else
          user.throttle_writes { user.settings.set!(checklist, updated_setting.to_json) }
        end

        GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.checklist.update", tags: stats_tags)
      end
    end

    def set_editors(user_id, editors)
      GitHub.dogstats.distribution_time("#{DOGSTATS_PREFIX}.redis.save", tags: stats_tags) do
        @redis.sadd("v1:user:#{user_id}:editors", editors)
      end
    rescue Redis::BaseConnectionError => err
      GitHub.logger.error("Redis failure for user #{user_id}: #{err.message}")
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.redis.processed_users", tags: stats_tags(["status:failure"]))
    end

    def pipeline_get_editors(user_ids)
      pipelined_editors = GitHub.dogstats.distribution_time("#{DOGSTATS_PREFIX}.redis.pipeline.get", tags: stats_tags) do
        @redis.pipelined do |pipeline|
          user_ids.each { |user_id| pipeline.smembers("v1:user:#{user_id}:editors") }
        end
      end

      user_ids.zip(pipelined_editors).to_h
    rescue Redis::BaseConnectionError => err
      # log and move on, since missing a few user_ids will
      # simply result in us re-querying kusto
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.redis.pipeline.error", tags: stats_tags)
      GitHub.logger.error("Redis pipeline failure: #{err.message}")
      {}
    end

    def prune_known_vscode_user_ids(user_ids, usage_data)
      user_ids.reject { |id| usage_data[id]&.include?("vscode") }
    end

    def get_existing_usage_data(user_ids)
      usage_data = {}
      user_ids.in_groups_of(REDIS_PIPELINE_BATCH_SIZE, false) do |batch|
        editors = pipeline_get_editors(batch)
        if editors.empty?
          next
        end
        usage_data.merge!(editors)
      end

      usage_data
    end

    def stats_tags(additional_tags = [])
      default_tags = ["dry_run:#{@dry_run}"]
      default_tags + additional_tags
    end

    def dry_run_output(message)
      if @dry_run && !Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        puts message
      end
    end
  end
end
