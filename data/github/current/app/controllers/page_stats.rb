# typed: true
# frozen_string_literal: true

class PageStats
  attr_accessor :entity
  attr_reader :action_name, :viewer, :pjax, :additional_tags

  def initialize(controller_name:, action_name:, viewer:, pjax:, additional_tags: [])
    @controller_name = controller_name
    @action_name = action_name
    @viewer = viewer
    @pjax = pjax
    @deferred_distributions = {}
    @deferred_render_distributions = []
    @additional_tags = additional_tags
  end

  # This is meant to be used in an around_action.
  def instrument_controller_action
    start_time = GitHub::Dogstats.monotonic_time
    Site::GlobalNoticeComponent.check_for_notices_elapsed = 0
    response_successful = yield

    return unless entity && response_successful

    if global_notice_elapsed = Site::GlobalNoticeComponent.check_for_notices_elapsed
      @deferred_distributions[:global_notice] = global_notice_elapsed
    end

    # All times in ms
    @deferred_distributions[:authzd] = GitHub::AuthzdInstrumenter.total_request_time
    @deferred_distributions[:memcache] = GitHub::Cache::Client.query_time * 1000
    @deferred_distributions[:gitrpc] = GitRPCLogSubscriber.rpc_time * 1000
    @deferred_distributions[:mysql] = GitHub::MysqlInstrumenter.query_time * 1000

    elapsed = GitHub::Dogstats.duration(start_time)

    GitHub.dogstats.distribution(
      "#{@controller_name}.#{action_name}.dist.time",
      elapsed,
      tags: stats_tags,
    )

    @deferred_distributions.each do |name, value|
      GitHub.dogstats.distribution(
        "#{@controller_name}.#{action_name}.#{name}.dist.time",
        value,
        tags: stats_tags
      )
    end

    @deferred_render_distributions.each do |render|
      GitHub.dogstats.distribution(
        "#{@controller_name}.#{action_name}.render.dist.time",
        render.fetch(:elapsed),
        tags: stats_tags + ["partial:#{render.fetch(:name)}"]
      )
    end
  end

  # Record a distribution timing metric.
  #  - include_net: if true, emit an additional metric that subtracts out
  #    the cost of data access.  Possibly useful when measuring the overhead
  #    of code which also fetches data (e.g. graphql)
  def record_distribution(name, include_net: false)
    if include_net
      before = {
        authzd: GitHub::AuthzdInstrumenter.total_request_time,
        cache: GitHub::Cache::Client.query_time,
        flipper: FlipperSubscriber.total_enabled_duration,
        gitrpc: GitRPCLogSubscriber.rpc_time,
        mysql: GitHub::MysqlInstrumenter.query_time
      }
    end
    start_time = GitHub::Dogstats.monotonic_time
    result = yield
    elapsed = GitHub::Dogstats.duration(start_time)
    @deferred_distributions[name] = elapsed
    store_net_metric(name, elapsed, before) if include_net
    result
  end

  # Record a partial render timing metric.
  def record_render(renderable_name)
    start_time = GitHub::Dogstats.monotonic_time
    result = yield
    elapsed = GitHub::Dogstats.duration(start_time)
    @deferred_render_distributions << {
      name: renderable_name,
      elapsed: elapsed,
    }
    result
  end

  # Allows a tag to be added during the yielded blocks
  def add_tags(*tags)
    # Ensure stats tags has been initialized
    stats_tags

    @_stats_tags += tags
  end

  private

  def store_net_metric(name, elapsed, before)
    offset = 0
    offset += (GitHub::AuthzdInstrumenter.total_request_time - before[:authzd]) * 1000
    offset += (GitHub::Cache::Client.query_time - before[:cache]) * 1000
    offset += (FlipperSubscriber.total_enabled_duration - before[:flipper])
    offset += (GitRPCLogSubscriber.rpc_time - before[:gitrpc]) * 1000
    offset += (GitHub::MysqlInstrumenter.query_time - before[:mysql]) * 1000
    @deferred_distributions["#{name}_net"] = elapsed - offset
  end

  def stats_tags
    return @_stats_tags if defined?(@_stats_tags)

    @_stats_tags = []

    viewer_tag_value =
      if viewer&.site_admin?
        "site_admin"
      elsif viewer
        "user"
      else
        "anonymous"
      end

    @_stats_tags << "viewer:#{viewer_tag_value}"
    @_stats_tags << "pjax:#{!!pjax}"
    @_stats_tags.concat(additional_tags) if additional_tags.present?
    @_stats_tags
  end
end
