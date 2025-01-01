# typed: true
# frozen_string_literal: true

class RestApiPaginatePullsExperimentJob < ApplicationJob
  use_replicas ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1

  retry_on_dirty_exit

  queue_as :rest_api_paginate_pulls_experiment

  include Scientist

  # This experiment is to validate our approach of rewriting a bad query in a better way.
  # More details can be found in the following issue: https://github.com/github/pull-requests/issues/16433
  def perform(repository_id:, user_id:, indifferent_params:, params:, pagination:)
    return if GitHub.enterprise?
    repo = Repositories::Public.get_active_or_deleted(repository_id)

    return unless repo
    return unless user_id

    user = User.find(user_id)
    @pagination = pagination

    pull_requests_sorted_by_pull_requests_table(repo, user, indifferent_params, params)
  end

  # This method is copied from the api/pulls.rb to run the experiment asynchronously.
  def pull_requests_sorted_by_pull_requests_table(repo, user, indifferent_params, params)
    pulls =
      if repo&.feature_enabled?(:only_filter_by_user_if_user_spammy)
        repo.pull_requests.filter_spam_for(user, skip_user_filter_if_not_spammy: true)
      else
        repo.pull_requests.filter_spam_for(user)
      end

    if head_label = params[:head]
      head_ref, head_owner = head_label.split(":").reverse
      if head_owner
        head_repo = Repositories.domain.networks.find_fork_in_network_for_user(repo, head_owner)
        pulls = pulls.for_head_repo_and_head_ref(head_repo, head_ref)
      end
    end

    if base_ref = params[:base]
      pulls = pulls.for_base_ref(base_ref).where("pull_requests.base_repository_id = pull_requests.repository_id")
    end

    pulls_filtered_and_ordered = pulls.filtered_and_ordered(indifferent_params)

    pulls = science "pull_requests.bad_query_rewrite" do |e|
      e.use do
        original_query(pulls_filtered_and_ordered, indifferent_params, repo)
      end

      e.try "page-with-index-hint" do
        optimized_query_with_index_hint(pulls_filtered_and_ordered, indifferent_params)
      end

      e.try "page-with-index-hint-and-minimum-page-zero" do
        optimized_query_with_index_hint_and_min_page_zero(pulls_filtered_and_ordered, indifferent_params)
      end

      e.try "page-exp-minimum-page-nine" do
        optimized_query_min_page_nine(pulls_filtered_and_ordered)
      end

      e.try "page-exp-minimum-page-zero" do
        optimized_query_min_page_zero(pulls_filtered_and_ordered)
      end

      e.compare_record_sequence
    end
  end

  def original_query(pulls_filtered_and_ordered, indifferent_params, repo)
    GitHub.tracer.in_span("RestApiPaginatePullsExperimentJob#original_query", kind: :internal) do
      GitHub.dogstats.distribution_time("experiment.pull_request.query_rewrite", tags: ["method:original_query"]) do
        results = paginate_rel(pulls_filtered_and_ordered)

        state = indifferent_params[:state]
        should_rewrite_join = if repo.feature_enabled?(:pull_requests_api_count_index_hint_more_often)
          state != "all"
        else
          state.present? && state != "all"
        end

        if should_rewrite_join
          # This works around a performance problem, where the MySQL query optimiser
          # will select the unique `pull_request_id` index over a non-unique index
          # that covers all of the fields in the `WHERE` clause.
          # See: https://github.com/github/killed-query-dashboard-updater/issues/913
          counter_scope = results.unscope(:joins).joins(Arel.sql(<<-SQL))
            INNER JOIN `issues` IGNORE INDEX (`index_issues_on_pull_request_id_unique`)
            ON `issues`.`pull_request_id` = `pull_requests`.`id`
          SQL
          results.total_entries = counter_scope.total_entries # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
        results.load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  def optimized_query_with_index_hint(pulls_filtered_and_ordered, indifferent_params)
    GitHub.tracer.in_span("RestApiPaginatePullsExperimentJob#optimized_query_with_index_hint", kind: :internal) do
      GitHub.dogstats.distribution_time("experiment.pull_request.query_rewrite", tags: ["method:optimized_query_with_index_hint"]) do
        state = indifferent_params[:state]
        should_rewrite_join = state.present? && state != "all"
        results = paginate_rel_fast_page_experiment(pulls_filtered_and_ordered)
        if should_rewrite_join
          # This works around a performance problem, where the MySQL query optimiser
          # will select the unique `pull_request_id` index over a non-unique index
          # that covers all of the fields in the `WHERE` clause.
          # See: https://github.com/github/killed-query-dashboard-updater/issues/913
          counter_scope = results.unscope(:joins).joins(Arel.sql(<<-SQL))
            INNER JOIN `issues` IGNORE INDEX (`index_issues_on_pull_request_id_unique`)
            ON `issues`.`pull_request_id` = `pull_requests`.`id`
          SQL
          results.total_entries = counter_scope.total_entries # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
        results.load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  def optimized_query_with_index_hint_and_min_page_zero(pulls_filtered_and_ordered, indifferent_params)
    GitHub.tracer.in_span("RestApiPaginatePullsExperimentJob#optimized_query_with_index_hint_and_min_page_zero", kind: :internal) do
      GitHub.dogstats.distribution_time("experiment.pull_request.query_rewrite", tags: ["method:optimized_query_with_index_hint_and_min_page_zero"]) do
        state = indifferent_params[:state]
        should_rewrite_join = state.present? && state != "all"
        results = paginate_rel_fast_page_experiment(pulls_filtered_and_ordered, experiment_min_page: 0)
        if should_rewrite_join
          # This works around a performance problem, where the MySQL query optimiser
          # will select the unique `pull_request_id` index over a non-unique index
          # that covers all of the fields in the `WHERE` clause.
          # See: https://github.com/github/killed-query-dashboard-updater/issues/913
          counter_scope = results.unscope(:joins).joins(Arel.sql(<<-SQL))
            INNER JOIN `issues` IGNORE INDEX (`index_issues_on_pull_request_id_unique`)
            ON `issues`.`pull_request_id` = `pull_requests`.`id`
          SQL
          results.total_entries = counter_scope.total_entries
        end
        results.load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  def optimized_query_min_page_zero(pulls_filtered_and_ordered)
    GitHub.tracer.in_span("RestApiPaginatePullsExperimentJob#optimized_query_min_page_zero", kind: :internal) do
      GitHub.dogstats.distribution_time("experiment.pull_request.query_rewrite", tags: ["method:optimized_query_min_page_zero"]) do
        paginate_rel_fast_page_experiment(pulls_filtered_and_ordered, experiment_min_page: 0).load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  def optimized_query_min_page_nine(pulls_filtered_and_ordered)
    GitHub.tracer.in_span("RestApiPaginatePullsExperimentJob#optimized_query_min_page_nine", kind: :internal) do
      GitHub.dogstats.distribution_time("experiment.pull_request.query_rewrite", tags: ["method:optimized_query_min_page_nine"]) do
        paginate_rel_fast_page_experiment(pulls_filtered_and_ordered).load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  # This method is copied from the api/app.rb to run the experiment asynchronously
  def paginate_rel(rel, pagination_opts = nil, skip_total_entries_count: false)
    pagination_opts ||= @pagination

    if rel.respond_to?(:limit)
      paginated_rel = rel.limit(pagination_opts[:per_page]).page(pagination_opts[:page])
      if pagination_opts[:total_entries] && !skip_total_entries_count
        capped_count = rel.unscoped.from(
          rel.unscope(:order, :select).select("1 as one").limit(pagination_opts[:total_entries]),
        ).count
        paginated_rel.total_entries = capped_count
      end
      paginated_rel
    elsif rel.respond_to?(:paginate)
      rel.paginate(page: pagination_opts[:page], per_page: pagination_opts[:per_page])
    else
      WillPaginate::Collection.create(pagination_opts[:page], pagination_opts[:per_page],
                                      rel.length) do |pager|
        # cast nil, or, say, `Google::Protobuf::RepeatedField` types into `Array`
        pager.replace(Array(rel)[pager.offset, pager.per_page])
      end
    end
  end

  # Once we graduate this experiment, we can add it to the api/app.rb
  def paginate_rel_fast_page_experiment(rel, experiment_min_page: nil, pagination_opts: nil, skip_total_entries_count: false)
    pagination_opts ||= @pagination

    if rel.respond_to?(:limit)
      paginated_rel = rel.limit(pagination_opts[:per_page]).page(pagination_opts[:page])

      if pagination_opts[:total_entries] && !skip_total_entries_count
        capped_count = rel.unscoped.from(
          rel.unscope(:order, :select).select("1 as one").limit(pagination_opts[:total_entries]),
        ).count
        paginated_rel.total_entries = capped_count
      end

      experiment_min_page ||= 9
      # Benchmarking shows that this is faster than 9 is the best page size
      # to use the new optimzed way of paginating.
      # More details: https://github.com/github/pull-requests/issues/16433#issuecomment-2722391921
      if pagination_opts[:page] && pagination_opts[:page] > experiment_min_page
        joined_rel = rel.where(id: rel.unscoped.select("*").from(paginated_rel.reselect(:id), "_inner"))

        joined_rel.extend(WillPaginate::ActiveRecord::RelationMethods)
        joined_rel.current_page = paginated_rel.current_page
        joined_rel.per_page     = paginated_rel.per_page
        joined_rel.total_entries = paginated_rel.total_entries # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        joined_rel
      else
        paginated_rel
      end
    elsif rel.respond_to?(:paginate)
      rel.paginate(page: pagination_opts[:page], per_page: pagination_opts[:per_page])
    else
      WillPaginate::Collection.create(pagination_opts[:page], pagination_opts[:per_page],
                                      rel.length) do |pager|
        # cast nil, or, say, `Google::Protobuf::RepeatedField` types into `Array`
        pager.replace(Array(rel)[pager.offset, pager.per_page])
      end
    end
  end
end
