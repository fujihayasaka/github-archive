# typed: true
# frozen_string_literal: true

module ActionsMetrics
  module FilterSuggestionsHelper
    include Kernel
    def search_org_repos(org, user, q, user_session: nil)
      if q&.present?
        query = Search::Queries::RepoQuery.new(
          current_user: user,
          phrase: q,
          page: 0,
          sort: %w(updated desc),
          per_page: limit,
          user_session: user_session,
          include_forks: true,
          binary_fork_filter: true,
        )

        query.qualifiers[:org].clear.must org.display_login
        query.qualifiers[:user].clear
        query.qualifiers[:owner].clear
        query.qualifiers[:repo].clear

        search = query.execute

        items = search.results.map { |r| r["_model"] }.to_a
        items.map { |r| r.name }
      else
        results = org.visible_repositories_for(user).where(owner_id: org).recently_updated.limit(limit)
        repo_names = results.to_a.map { |r| r.name }

        repo_names
      end
    end

    def search_org_workflows(org, request_options)
      client = ActionsMetrics::Client.new(org: org, timeout: 10).client

      request = ActionsUsageMetrics::Api::V1::GetWorkflowsRequest.new(
        request_options: request_options
      )

      response = client.get_workflows(request: request)
      response.data.workflows.map { |w| w.file_name }.to_a
    end

    def search_org_jobs(org, request_options)
      client = ActionsMetrics::Client.new(org: org, timeout: 10).client

      request = ActionsUsageMetrics::Api::V1::GetJobsRequest.new(
        request_options: request_options
      )

      response = client.get_jobs(request: request)
      response.data.jobs.map { |j| j.job_name }.to_a
    end

    def limit
      8
    end
  end
end
