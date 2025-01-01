# typed: true
# frozen_string_literal: true

require "github/tagging_helper"

module ApplicationController::StatsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :staff_bar_enabled?
    helper_method :stats_ui_enabled?
    helper_method :render_graphql_query_trace?
    helper_method :render_mysql_query_trace?
    helper_method :browser_stats_enabled?
    helper_method :render_api_insights?
    helper_method :dogstats_request_tags
    helper_method :dogstats_staff_request_tags
  end

  protected

  # Public: Check if staff bar should be displayed
  #
  # Returns Boolean.
  def staff_bar_enabled?
    real_user_site_admin? || employee?
  end

  # Public: Check if staff stats should be collected and displayed.
  #
  # Use regular site-admin/employee check rather than the true check so
  # disabling site-admin will turn off stats as well.
  #
  # Returns Boolean.
  def stats_ui_enabled?
    (real_user_site_admin? || employee?) && GitHub.stats_ui_enabled?
  end

  # Check to see if we should render detailed GraphQL query information in the
  # page for debugging purposes.
  #
  # Returns Boolean
  def render_graphql_query_trace?
    return false unless stats_ui_enabled?
    params[:graphql_query_trace] && Platform::GlobalScope.queries.any?
  end

  # Check to see if we should render detailed Mysql query information in the
  # page for debugging purposes.
  #
  # Returns Boolean
  def render_mysql_query_trace?
    return false unless stats_ui_enabled?
    params[:mysql_query_trace]
  end

  # Check to see if we should render detailed GraphQL/Rest query information in the
  # page for debugging purposes.
  #
  # Returns Boolean
  def render_api_insights?
    return false unless stats_ui_enabled?
    params[:_tracing]
  end

  # Public: Check if browser stats should be collected
  def browser_stats_enabled?
    GitHub.browser_stats_enabled?
  end

  # Public: Dogstats tags for the current request
  #
  # Use these tags for your GitHub.dogstats calls. We do not add them automatically
  # because of the limitations of DataDog tag values.
  #
  # Returns Array of Strings
  def dogstats_request_tags
    unless defined?(@dogstats_request_tags)
      @dogstats_request_tags = [
        "controller:#{T.must(self.class.name).underscore}".freeze,
        "action:#{action_name}".freeze,
      ]
    end

    @dogstats_request_tags.dup
  end

  # Public: Dogstats staff tags for the current request
  #
  # Use these tags for your GitHub.dogstats calls. We do not add them automatically
  # because of the limitations of DataDog tag values.
  #
  # Returns Array of Strings
  def dogstats_staff_request_tags
    unless defined?(@dogstats_staff_request_tags)
      @dogstats_staff_request_tags = [
        GitHub::TaggingHelper.is_staff?(request.env) ? "is_staff:true" : "is_staff:false",
      ]
    end

    @dogstats_staff_request_tags.dup
  end

  # Public: Setter for the current request wide statsd sampling rate
  #
  # This sets the sampling rate we use when emitting metrics via statsd.  The
  # default should be fine in most cases, but high traffic controllers or
  # actions may want to set the sampling rate to something fairly small, like
  # 0.01 or 0.001.  This expects the rate to be a float between 1.0 and 0.0.
  class_methods do
    def set_statsd_sample_rate(rate, options = {})
      T.bind(self, T.class_of(ApplicationController))
      before_action(options) do
        T.bind(self, ApplicationController)
        request.env[GitHub::TaggingHelper::STATSD_SAMPLE_RATE] = rate
      end
    end

    def track_latency_slo(slo_name, max_ms, options = {})
      T.bind(self, T.class_of(ApplicationController))
      before_action(options) do
        T.bind(self, ApplicationController)
        slos = GitHub::TaggingHelper.tracked_latency_slos(request.env)
        request.env[GitHub::TaggingHelper::TRACKED_LATENCY_SLOS] = slos.merge({ slo_name => max_ms })
      end
    end

    def track_availability_slo(slo_name, options = {})
      T.bind(self, T.class_of(ApplicationController))
      before_action(options) do
        T.bind(self, ApplicationController)
        slos = GitHub::TaggingHelper.tracked_availability_slos(request.env)
        request.env[GitHub::TaggingHelper::TRACKED_AVAILABILITY_SLOS] = slos + [slo_name]
      end
    end
  end

  # Public: Getting for current request wide statsd sampling rate
  #
  # This returns the request side statsd sampling rate.  This is intended to
  # be used by individual controllers to get the sampling rate they should use
  # for ad-hoc metrics reporting.
  def statsd_sample_rate
    request.env[GitHub::TaggingHelper::STATSD_SAMPLE_RATE]
  end

  def staff_platform_loader_tracker
    return yield unless staff_bar_enabled?

    Platform::LoaderTracker.collect_staffbar_details do
      yield
    end
  end

  # Instruments rails templates and models for staffbar-enabled requests
  def staff_rails_instrumentation
    # Check the stats cookie directly, since we run before the before_action(:set_site_admin_and_employee_status)
    return yield unless stats_ui_enabled?
    return yield unless defined?(ActionView::Template.template_trace)

    begin
      ActionView::Template.template_trace_reset
      ActionView::Template.template_trace_enabled = true
      yield
    ensure
      ActionView::Template.template_trace_enabled = false
    end
  end

  # Instruments rails templates. Currently used by IssuesController#show
  def track_and_report_render_view_time
    return yield unless defined?(ActionView::Template.template_trace)

    begin
      ActionView::Template.template_trace_reset
      ActionView::Template.template_trace_enabled = true

      yield

      total_render_time = ActionView::Template.template_trace.total_time

      event_tags = ["controller:#{controller_name}", "action:#{action_name}"]
      GitHub.dogstats.distribution("request.render.time", (total_render_time * 1000).round(3), tags: event_tags)
    ensure
      ActionView::Template.template_trace_enabled = false
    end
  end

  # Collects MySQL query info for staff.
  def staff_mysql_instrumentation
    return yield unless stats_ui_enabled?

    GitHub::MysqlInstrumenter.with_track do
      yield
    end
  end

  def staff_api_insights_instrumentation
    return yield unless render_api_insights?
    GitHub::MysqlInstrumenter.with_track do
      @api_insights_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @api_insights_start_allocated_objects = GC.stat(:total_allocated_objects)
      yield
    end
  end

  # Collects GraphQL query info and reports it to DataDog
  # This only reports generic query info (query_time and query_count) during the given controller action.
  # This does not track detailed info for individual queries
  def track_and_report_graphql_executions
    before_query_count = Platform::GlobalScope.query_count
    before_query_time = Platform::GlobalScope.query_time

    yield

    after_query_count = Platform::GlobalScope.query_count
    after_query_time = Platform::GlobalScope.query_time

    event_tags = ["controller:#{controller_name}", "action:#{action_name}"]

    total_query_time = after_query_time - before_query_time
    GitHub.dogstats.distribution("request.graphql.execution.time", (total_query_time * 1000).round(3), tags: event_tags)

    total_query_count = after_query_count - before_query_count
    GitHub.dogstats.distribution("request.graphql.execution.count", total_query_count, tags: event_tags)
  end

  # Collects MySQL executions info and reports it to DataDog
  # This only reports generic SQL executions (query_time and query_count) during the given controller action.
  # This does not track detailed SQL info for individual query execution.
  def track_and_report_mysql_executions
    before_query_count = GitHub::MysqlInstrumenter.query_count
    before_query_time = GitHub::MysqlInstrumenter.query_time

    yield

    after_query_count = GitHub::MysqlInstrumenter.query_count
    after_query_time = GitHub::MysqlInstrumenter.query_time

    event_tags = ["controller:#{controller_name}", "action:#{action_name}"]

    total_query_time = after_query_time - before_query_time
    GitHub.dogstats.distribution("request.mysql.execution.time", (total_query_time * 1000).round(3), tags: event_tags)

    total_query_count = after_query_count - before_query_count
    GitHub.dogstats.distribution("request.mysql.execution.count", total_query_count, tags: event_tags)
  end

  def report_api_insights_information(args)
    return unless @api_insights_start_time && @api_insights_start_allocated_objects && !params[:flamegraph]

    total_allocated_objects = GC.stat(:total_allocated_objects) - @api_insights_start_allocated_objects
    total_api_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @api_insights_start_time

    # args must be an array where the first element is a hash with json data
    return unless args && args.is_a?(Array) && args.first && args.first.is_a?(Hash) && args.first[:json]

    data = if args.first[:json].is_a?(Hash)
      # do not mutate original arguments
      args.first[:json].dup
    elsif args.first[:json].is_a?(String)
      GitHub::JSON.parse(args.first[:json], failsafe: true)
    end

    # don't add the trace data to the response if it's already there (happening when executing GraphQL queries via the internal graphql controller)
    return if data.nil? || data["__trace"]

    queries = GitHub::MysqlInstrumenter.queries.map do |query|
      {
        sql: query.sql,
        digested_sql: query.digested_sql,
        duration_ms: query.duration * 1000,
        backtrace: query.backtrace.take(5).map { |location| location.to_s },
        result_count: query.result_count
      }
    end

    data[:__trace] = {
      query_name: request.path,
      query_variables: request.params,
      method: request.method,
      url: request.url,
      sql_queries: queries,
      verified_fetch: use_verified_fetch?,
      total: {
        duration_ms: total_api_time * 1000,
        allocated_objects_count: total_allocated_objects,
      }
    }

    # keep other keys as part of the render arguments
    { **args.first, json: data }
  end

  # Collects GitRPC/Redis/MySQL query info for staff.
  def staff_external_service_profiler
    return yield unless stats_ui_enabled?
    GitRPCLogSubscriber.track = true
    Redis::Client.track = true
    GitHub::Goomba::WarpPipeStats.enable_stats_bar_tracking
    yield
  ensure
    GitRPCLogSubscriber.track = false
    Redis::Client.track = false
  end

  def trace_web_request
    attributes = {
      GitHub::TaggingHelper::COMPONENT_TAG => "rails",
      GitHub::TaggingHelper::CONTROLLER_TAG => GitHub::TaggingHelper.controller(request.env),
      GitHub::TaggingHelper::ACTION_TAG => params[:action],
      GitHub::TaggingHelper::CATEGORY_TAG => GitHub::TaggingHelper.category(request.env),
      GitHub::TaggingHelper::RAILS_VERSION_TAG => GitHub::TaggingHelper.rails_version,
      GitHub::TaggingHelper::LOGGED_IN_TAG => GitHub::TaggingHelper.logged_in(request.env),
      GitHub::TaggingHelper::IS_ROBOT_TAG => GitHub.robot?(request.user_agent.to_s),
      GitHub::TaggingHelper::PJAX_TAG => GitHub::TaggingHelper.pjax(request.env),
      "enduser.id" => trace_employee_login,
      "gh.user.id" => current_user&.id
    }.compact

    GitHub.current_span&.tap do |span|
      span.name = "#{request.request_method} #{params[:controller]}/#{params[:action]}"
      span.add_attributes(attributes)
    end
  end

  def trace_employee_login
    if current_user
      current_user.employee? ? current_user.display_login : "REDACTED"
    end
  end
end
