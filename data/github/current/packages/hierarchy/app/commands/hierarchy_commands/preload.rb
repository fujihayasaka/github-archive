# typed: true
# frozen_string_literal: true

# This command class calls out to the IssuesGraph service to fetch hierarchy
# data for a given issue. It then wraps the raw data in a Hierarchy object and
# hangs the hierarchy object off of the issue.
module HierarchyCommands
  class Preload
    extend T::Sig

    # TODO: adjust this value down once we have a better idea of denormalized
    # lag time. This seems like it can be pretty high in codespace development,
    # but in production should be much lower.
    # This comment was moved over from its original location ☝️
    LAST_MODIFIED_AT_MIN_AGE_FOR_DENORMALIZED_GET = 10.seconds
    STATS_KEY = "hierarchy_commands.preload"
    STATS_KEY_SYNCED = "hierarchy_commands.preload.sync_check"

    CACHE_STATS_KEY = "issues_graph.sync_hierarchy_state.cache"
    ISSUES_GRAPH_CACHE_TTL = 5.seconds

    sig do
      params(
        issue: Issue,
        repository: Repository,
        owner: T.any(User, Organization),
        viewer: T.nilable(User),
        dependencies: T::Hash[Symbol, T.untyped],
      ).returns(Promise[::HierarchyCommands::Result])
    end
    def self.async_maybe_preload(issue:, repository:, owner:, viewer: nil, dependencies: {})
      return Promise.resolve(HierarchyCommands::Result.new(success: true)) if issue.hierarchy_loaded?
      HierarchyCommands::Preload.new(
        issue: issue,
        repository: repository,
        owner: owner,
        viewer: viewer,
        dependencies: dependencies
      ).async_call
    end

    sig do
      params(
        issue: Issue,
        repository: Repository,
        owner: T.any(User, Organization),
        viewer: T.nilable(User),
        dependencies: T::Hash[Symbol, T.untyped],
      ).void
    end
    def initialize(issue:, repository:, owner:, viewer: nil, dependencies: {})
      @issue = issue
      @repository = repository
      @owner = owner
      @viewer = viewer

      @tracer = dependencies[:tracer] || GitHub::Telemetry.tracer(self.class.name)
      @issues_graph_api_client = dependencies[:issues_graph_api_client] ||
        GitHub.issues_graph_api_client_strict
      @async_issues_graph_api_client = dependencies[:async_issues_graph_api_client] ||
        GitHub.async_issues_graph_api_client
      @stats = dependencies[:stats_class] || GitHub.dogstats
    end

    sig { returns(::HierarchyCommands::Result) }
    def call
      return bail_early_for_pull_requests if @issue.pull_request?

      @tracer.in_span("#call") do
        @stats.distribution_time(STATS_KEY) do
          @issues_graph_call_result = preload_hierarchy_state
        end
      end

      if @issues_graph_call_result&.success?
        @issue.hierarchy_raw = @issues_graph_call_result
        check_if_synced
        HierarchyCommands::Result.new(success: true)
      else
        @issue.hierarchy_raw = @issues_graph_call_result || null_result
        HierarchyCommands::Result.new(success: false)
      end
    end

    sig { returns(Promise[::HierarchyCommands::Result]) }
    def async_call
      return Promise.resolve(bail_early_for_pull_requests) if @issue.pull_request?

      @tracer.in_span("#async_call") do
        @stats.distribution_time(STATS_KEY) do
          async_hierarchy_state.then do |preload_hierarchy_state|
            @issues_graph_call_result = preload_hierarchy_state
            if @issues_graph_call_result&.success?
              @issue.hierarchy_raw = @issues_graph_call_result
              Promise.resolve(HierarchyCommands::Result.new(success: true))
            else
              @issue.hierarchy_raw = @issues_graph_call_result || null_result
              Promise.resolve(HierarchyCommands::Result.new(success: false))
            end
          end
        end
      end
    end

    private

    sig { void }
    def check_if_synced
      last_updated_sql = (@issue.edited_at || @issue.updated_at)&.to_i
      last_updated_ig = @issues_graph_call_result.data.try(:issue)&.timestamp

      if last_updated_ig && last_updated_sql
        @issue.hierarchy_synced = last_updated_sql <= last_updated_ig
      end

      if @issue.hierarchy_synced?
        GitHub.dogstats.increment(
          STATS_KEY_SYNCED,
          tags: [
            "synced:true",
            "pipeline_strategy:#{pipeline_strategy}",
          ]
        )
      else
        GitHub.logger.error(
          "issue hierarchy not synced",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.catalog_service": "github/issues-graph",
          "gh.repository_id": @repository.id,
          "gh.issue_id": @issue.id,
          "gh.issues_graph.pipeline_strategy": pipeline_strategy,
        )
        GitHub.dogstats.increment(
          STATS_KEY_SYNCED,
          tags: [
            "synced:false",
            "pipeline_strategy:#{pipeline_strategy}",
          ]
        )
      end

      nil
    end

    sig { returns(String) }
    def pipeline_strategy
      GitHub.flipper[:tasklist_block_precache].enabled?(@repository.owner) ? "precache" : "md-at-rest"
    end

    sig { returns(::HierarchyCommands::Result) }
    def bail_early_for_pull_requests
      @issue.hierarchy_raw = null_result(error_message: "issue is a pull request")
      HierarchyCommands::Result.new(success: true)
    end

    sig { params(error_message: String).returns(::IssuesGraph::Result) }
    def null_result(error_message: "no result returned")
      IssuesGraph::Result.new(error: Struct.new(:message).new(error_message))
    end

    sig { returns(T.nilable(::IssuesGraph::Result)) }
    def preload_hierarchy_state
      if @repository.feature_enabled?(:issues_graph_api_concurrent_faraday)
        async_hierarchy_state&.sync
      else
        sync_hierarchy_state
      end
    end

    sig { returns(T.nilable(::IssuesGraph::Result)) }
    def sync_hierarchy_state
      return unless @issue.persisted? && tasklist_blocks_enabled?
      return unless GitHub.flipper[:issue_hierarchy_state].enabled?

      unless GitHub.flipper[:hierarchy_cache_key].enabled?
        return @issues_graph_api_client.get_issue(
          **common_get_issue_options,
          stat_tags: ["context:sync_hierarchy_state"]
        )
      end

      response = GitHub.cache.fetch(get_issue_cache_key, ttl: ISSUES_GRAPH_CACHE_TTL, stats_key: CACHE_STATS_KEY) do
        client_response = @issues_graph_api_client.get_issue(
          **common_get_issue_options,
          stat_tags: ["context:sync_hierarchy_state"]
        )

        # Convert response object to json string for caching
        jsonify_hierarchy_state(client_response)
      end

      response_hash = JSON.parse(response)
      unless response_hash["status"] == "success"
        get_issue_error = Twirp::Error.new(response_hash["error_code"], response_hash["error_message"])
        return ::IssuesGraph::Result.error(get_issue_error)
      end

      # Rehydrate cached content into expected response object
      get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(**response_hash["data"])
      ::IssuesGraph::Result.success(get_issue_response)
    end

    sig { returns(String) }
    def get_issue_cache_key
      [
        "v0",
        "issues_graph",
        "get_issue",
        @viewer&.id,
        @repository.owner_id,
        @issue.id, # issue/item id
        @issue.updated_at.to_i,
      ].join(":")
    end

    # Nested objects need to be converted to hashes before being converted to
    # json to prevent data loss.
    sig do
      params(
        issues_graph_response: T.untyped,
      ).returns(String)
    end
    def jsonify_hierarchy_state(issues_graph_response)
      data_hash = issues_graph_response&.data.to_h
      issues_graph_hash = issues_graph_response.to_h
      issues_graph_hash[:data] = data_hash
      issues_graph_hash.to_json
    end

    sig { returns(T.nilable(Promise[T.untyped])) }
    def async_hierarchy_state
      return unless @issue.persisted? && tasklist_blocks_enabled?
      return unless GitHub.flipper[:issue_hierarchy_state].enabled?

      @async_issues_graph_api_client.get_issue(
        **common_get_issue_options,
        stat_tags: ["context:async_hierarchy_state"]
      )
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def common_get_issue_options
      {
        use_denormalized_data: !disable_denormalized_read?,
        key: @issue.to_hierarchy_model_key,
      }
    end

    sig { returns(T::Boolean) }
    def disable_denormalized_read?
      modified_age = Time.current - @issue.updated_at
      modified_very_recently = modified_age < LAST_MODIFIED_AT_MIN_AGE_FOR_DENORMALIZED_GET
      feature_symbol = :issues_graph_api_disable_denormalized_read

      !!(modified_very_recently ||
         @repository.feature_enabled?(feature_symbol) ||
         @viewer&.feature_enabled?(feature_symbol))
    end

    # Public: Determines if the issue supports tracking blocks.
    #
    # Returns true if issue supports tracking blocks, false otherwise.
    sig { returns(T::Boolean) }
    def tasklist_blocks_enabled?
      @owner.feature_enabled?(:tasklist_block)
    end
  end
end
