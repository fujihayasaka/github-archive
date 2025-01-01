# typed: true
# frozen_string_literal: true

module Search
  module Queries

    class WorkflowRunQuery < ::Search::Query

      # The set of fields that can be queried when performing a workflow run search
      def self.field_list
        [:sort, :status, :conclusion, :branch, :head_sha, :name, :event, :action, :workflow, :creator, :pusher, :is, :actor, :created, :check_suite_id].freeze
      end

      # The mapping of workflow_run-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "created"         => "created_at",
        "workflow_run_id" => "workflow_run_id",
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[created desc].freeze

      # Construct a WorkflowRunQuery. The query can be restricted to a single
      # repository by providing a :repo_id option.
      #
      # opts - The options Hash.
      #   :repo_id - The repository id to limit the query for
      #   :lab - Whether or not it should search only for lab workflow runs
      #
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::WorkflowRuns.new
        @repo_id = opts.fetch(:repo_id, nil)
        @head_repo_id = opts.fetch(:head_repo_id, nil)
        @unsupported_conclusions = opts.fetch(:unsupported_conclusions, nil)
        @lab = opts.fetch(:lab, nil)
        @workflow_id = opts.fetch(:workflow_id, nil)
        @hide_spammy_runs = opts.fetch(:hide_spammy_runs, false)
        @show_spammy_runs_by_current_user = opts.fetch(:show_spammy_runs_by_current_user, true)
        @aggregations_size = opts.fetch(:aggregations_size, 10)
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        params = { type: "workflow_run" }
        params[:routing] = @repo_id unless @repo_id.nil?
        params
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "name";  @query_fields << "name^1.2"
          end
        end

        @query_fields = %w[name^1.2 status] if @query_fields.empty?
        @query_fields
      end

      def build_query_filter
        filter = ::Search::Filters::BoolFilter.new(filter_hash, aggregations)
        query_filter = filter.build

        if query_filter[:bool][:should]
          query_filter[:bool][:minimum_should_match] = 1
        end

        query_filter
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        query = { query_string: {
          query: escaped_query,
          fields: query_fields,
          default_operator: "AND",
          analyzer: "lowercase",
        } }

        query = { function_score: {
          query: query,
          score_mode: "multiply",
          functions: [{
            field_value_factor: {
              field: "rank",
              missing: 1,
            },
          }],
        } }

        query
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      def aggregations_size
        @aggregations_size
      end

      # Internal: Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        filters[:check_suite_id] = builder.query_filter(:check_suite_id)
        filters[:name]           = builder.query_filter(:name) { |str| str.downcase }
        filters[:repo_id]        = builder.repository_filter(current_user, @repo_id, nil, user_session: user_session, ip: remote_ip)
        filters[:status]         = builder.query_filter(:status)
        filters[:workflow_name]  = builder.query_filter(:workflow_name, :workflow)
        filters[:head_branch]    = builder.query_filter(:head_branch, :branch)
        filters[:head_sha]       = builder.query_filter(:head_sha)
        filters[:event]          = builder.query_filter(:event)
        filters[:action]         = builder.query_filter(:action)
        filters[:creator]        = builder.query_filter(:creator)
        filters[:pusher]         = builder.query_filter(:pusher)
        filters[:is]             = builder.query_filter(:is)
        filters[:actor]          = builder.query_filter(:actor)
        filters[:title]          = builder.query_filter(:title)
        filters[:created_at]     = builder.date_range_filter(:created_at, :created)

        if @unsupported_conclusions
          qualifiers[:conclusion].clear.must_not(@unsupported_conclusions)
          qualifiers[:conclusion].must(Search::Filter::EXISTS) # exclude in-progress WorkflowRuns with conclusion:nil
          filters[:conclusion] = builder.term_filter(:conclusion)
        else
          filters[:conclusion] = builder.query_filter(:conclusion)
        end

        unless @head_repo_id.nil?
          filters[:head_repo_id] = builder.repository_filter(current_user, @head_repo_id, nil, user_session: user_session, ip: remote_ip, field: :head_repo_id)
        end

        unless @lab.nil?
          qualifiers[:lab].clear.must(@lab)
          filters[:lab] = builder.term_filter(:lab)
        end

        unless @workflow_id.nil?
          qualifiers[:workflow_id].clear.must(@workflow_id)
          filters[:workflow_id] = builder.term_filter(:workflow_id)
        end

        if @hide_spammy_runs
          if @show_spammy_runs_by_current_user && current_user.present?
            # Require user_hidden == false OR actor_id == current_user.id
            qualifiers[:user_hidden].clear.should(false)
            filters[:user_hidden] = builder.term_filter(:user_hidden)

            qualifiers[:actor_id].clear.should(current_user.id)
            filters[:actor_id] = builder.term_filter(:actor_id)
          else
            qualifiers[:user_hidden].clear.must(false)
            filters[:user_hidden] = builder.term_filter(:user_hidden)
          end
        end

        @filter_hash = filters
      end

      def valid_query?
        return false unless super

        if escaped_query.empty?
          if filter_hash.empty?
            @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
            return false
          end
        end

        true
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of workflow run results and remove those that
      # no longer exist in the database or have been flagged as spammy. We
      # will only perform this pruning in test and production; development
      # mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        workflow_run_ids = results.map { |h| h["_id"] }
        workflow_runs = if @repo_id.present?
          Actions::WorkflowRun.where(id: workflow_run_ids, repository_id: @repo_id).includes(:repository)
        else
          # In the case that @repo_id is not present, we want to send the query
          # to all shards, so this will remain exempt from sharding.
          Actions::WorkflowRun.annotate("cross-shard-query-exempted").where(id: workflow_run_ids).includes(:repository)
        end

        GitHub.dogstats.increment("search.query.workflow_run.no_repo") unless @repo_id.present?

        GitHub::PrefillAssociations.prefill_batch_method(workflow_runs, :trigger)
        GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, :workflow, :check_suite])

        workflow_runs = workflow_runs.index_by(&:id)

        results.delete_if do |h|
          workflow_run_id = h["_id"].to_i
          workflow_run = workflow_runs[workflow_run_id]

          if workflow_run.nil?
            RemoveFromSearchIndexJob.perform_later("workflow_run", workflow_run_id, @repo_id)
            true
          elsif workflow_run.check_suite.nil?
            # This might be due to replication lag - prune for now but don't remove from index
            true
          else
            if out_of_sync(workflow_run)
              Search.add_to_search_index("workflow_run", workflow_run.id)
              GitHub.dogstats.increment("workflow_runs.out_of_sync")
              true
            else
              h["_model"] = workflow_run
              next false unless @hide_spammy_runs && workflow_run.user_hidden?
              # Filtered out spammy runs but this run is spammy - trigger update
              Search.add_to_search_index("workflow_run", workflow_run.id)
              GitHub.dogstats.increment("workflow_runs.user_hidden_out_of_sync")

              next true unless @show_spammy_runs_by_current_user && current_user.present?
              current_user.id != workflow_run.actor_id
            end
          end
        end
      end

      def out_of_sync(workflow_run)
        params = Search::Queries::WorkflowRunQuery.parse(@phrase)
        params.each do |(key, value)|
          filters_conclusion = key == :conclusion || (key == :is && CheckSuite.conclusions.keys.include?(value))
          return true if filters_conclusion && workflow_run.conclusion != value

          filters_status = key == :status || (key == :is && CheckSuite.statuses.keys.include?(value))
          return true if filters_status && workflow_run.status != value
        end
        false
      end

    end  # WorkflowRunQuery
  end  # Queries
end  # Search
