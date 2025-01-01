# typed: true
# frozen_string_literal: true

module Platform
  # SubIssueFieldTracer is a custom tracer which records the time spent in sub-issue fields in the issue viewer
  # primary and secondary query.
  module SubIssueFieldTracer
    include Tracing::DefaultTracerBase
    include SubIssuesReactHelper

    def initialize(multiplex: nil, query: nil, **kwargs)
      @query = query
      @field_timing = 0
      @authorized_timing = 0
      super
    end

    def current_user
      return @current_user if defined?(@current_user)
      @current_user = @query&.context[:viewer]
    end

    def execute_multiplex(multiplex:)
      # The query wasn't available in `initialize`, but it is here,
      # so we should make some recordings.
      if !@query
        @query = multiplex.queries[0]
        Platform::GlobalScope.tracers << self
      end
      super
    end

    def platform_execute
      result = super
      after_sub_issue_field_trace
      result
    end

    def execute_field(field:, query:, ast_node:, arguments:, object:)
      execute_field_timing(query: query) do
        super
      end
    end

    def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
      execute_field_timing(query: query) do
        super
      end
    end

    def authorized(query:, type:, object:)
      authorized_timing(query: query) do
        super
      end
    end

    def authorized_lazy(query:, type:, object:)
      authorized_timing(query: query) do
        super
      end
    end

    private def is_sub_issue_descendant_field?(query)
      path = query.context.namespace(:interpreter)[:current_path]
      return unless path
      path.include?("subIssues") || path.include?("parent") || path.include?("subIssuesSummary")
    end

    private def is_issue_viewer_query?(query)
      query.operation_name == "IssueViewerSecondaryViewQuery" || query.operation_name == "IssueViewerViewQuery"
    end

    private def execute_field_timing(query:)
      return yield unless is_issue_viewer_query?(query) && is_sub_issue_descendant_field?(query)
      start_time = GitHub::Dogstats.monotonic_time
      res = yield
      @field_timing += GitHub::Dogstats.monotonic_time - start_time
      res
    end

    private def authorized_timing(query:)
      return yield unless is_issue_viewer_query?(query) && is_sub_issue_descendant_field?(query)
      start_time = GitHub::Dogstats.monotonic_time
      res = yield
      @authorized_timing += GitHub::Dogstats.monotonic_time - start_time
      res
    end

    private def after_sub_issue_field_trace
      return if @field_timing == 0
      tags = get_sub_issues_tags(@query.result.to_h["data"]) || []
      tags << "query:#{@query.operation_name}"

      GitHub.dogstats.distribution("platform.query.sub_issue_field_tracer.field_timing", @field_timing, tags:)
      GitHub.dogstats.distribution("platform.query.sub_issue_field_tracer.authorized_timing", @authorized_timing, tags:)
    end
  end
end
