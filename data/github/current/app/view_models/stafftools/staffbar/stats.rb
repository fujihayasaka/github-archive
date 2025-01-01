# typed: true
# frozen_string_literal: true

class Stafftools::Staffbar::Stats
  include GitHub::Memoizer
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TagHelper

  def profiling_enabled?
    GitHub.profiling_enabled?
  end

  attr_reader :request, :element_id_suffix

  def initialize(options = {})
    @request = options[:request]
    @element_id_suffix = options[:element_id_suffix] || ""
    @is_luc = ENV["LUC_PERFORMANCE"] == "1"
  end

  def enterprise?
    GitHub.enterprise?
  end

  def single_instance?
    GitHub.single_instance?
  end

  def xhr_stats
    nil
  end

  def process_stats
    @process_stats ||= @request.env[Rack::ProcessUtilization::ENV_KEY]
  end

  def luc?
    @is_luc
  end

  def site_stats
    @site_stats ||= GitHub::Stats.site(enterprise?)
  end

  def process_stat_tracked?(sym)
    process_stats && process_stats.send("track_#{sym}?")
  end

  def gc_info
    process_stats&.gc_info
  end

  def process_stat_visible?(sym)
    queries, time = process_stats.send("#{sym}_stats")
    time > 0.001
  end

  def process_stat(sym)
    format_stats process_stats.send(sym)
  end

  def server_status(sym)
    if site_stats
      classes = site_stats[sym] ? "dot active" : "dot inactive"
      content_tag(:span, "", class: classes) # rubocop:disable Rails/ViewModelHTML
    end
  end

  def format_stats(stats)
    queries, time = stats
    "#{format_time time} / #{queries}"
  end

  def gc_time
    return unless gc_info
    format_time gc_info.time
  end

  def allocations_scheme
    allocations = gc_info&.allocations.to_i
    return :default if !allocations || allocations <= 100_000
    return :attention if allocations <= 300_000
    :danger
  end

  def response_time_stats
    if sec = response_time_secs
      format_time sec
    end
  end

  def reaction_emoji
    return "🐇" if label_scheme == :success
    return "🐢" if label_scheme == :warning
    "🐌"
  end

  def label_scheme
    secs = response_time_secs
    return :success if secs <= 0.150
    return :warning if secs <= 0.450
    :danger
  end

  def response_time_secs
    if start_time = request.env["process.request_start"]
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    end
  end

  def nginx_queued_time_stats
    format_time nginx_queued_time_secs
  end

  def alloy_time_stats
    format_time alloy_time_secs
  end

  def label_summary
    unicorn_phrase = "unicorn"

    if alloy_time_stats != "0ms"
      unicorn_phrase += " (alloy: #{alloy_time_stats})"
    end

    [
      glb_to_ngnix_time_stats,
      "glb →",
      nginx_queued_time_stats,
      "nginx →",
      response_time_stats,
      reaction_emoji,
      unicorn_phrase
    ].join " "
  end

  def glb_to_ngnix_time_stats
    glb_to_nginx = glb_to_unicorn_time_secs - nginx_queued_time_secs
    format_time glb_to_nginx.clamp(0.0, Float::MAX)
  end

  def nginx_queued_time_secs
    if queued_time = request.env[GitHub::TaggingHelper::REQ_WAIT_TIME]
      ("%.5f" % queued_time).to_f
    else
      0.0
    end
  end

  def alloy_time_secs
    if alloy_time = request.env[GitHub::TaggingHelper::ALLOY_WAIT_TIME]
      ("%.5f" % (alloy_time / 1000.0)).to_f
    else
      0.0
    end
  end

  def glb_to_unicorn_time_secs
    if glb_to_unicorn = request.env[GitHub::TaggingHelper::GLB_WAIT_TIME]
      ("%.5f" % glb_to_unicorn).to_f
    else
      0.0
    end
  end

  def render_stats?
    process_stat_tracked?(:render) && ActionView::Template.template_trace_enabled
  end

  def render_stats_visible?
    process_stats.render_stats.total_time > 0
  end

  def render_time
    format_time process_stats.render_stats.total_time
  end

  def render_trace_html
    doc = Nokogiri::HTML(process_stats.render_stats.root.children_html)
    doc.css("span.name").each do |node|
      trace_line = create_trace_line_html(doc, node)
      node.inner_html = ""
      node.add_child(trace_line)
    end

    doc.css("body").first.inner_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  # Public: Creates an HTML link for a render trace line.
  #
  # html_document - Nokogiri::HTML::Document instance.
  # node          - HTML node with the text for the render trace line.
  #
  # Returns a link for the render trace line as a new Nokogiri::XML::Element instance.
  def create_trace_line_html(html_document, node)
    html_document.create_text_node node.text
  end

  def cpu_stats
    return unless process_stats
    cpu, idle, _real = process_stats.cpu_stats
    format_time(cpu + idle)
  end

  def gc_count_by_type
    "#{gc_info.minor_count} minor / #{gc_info.major_count} major"
  end

  def obj_allocated
    number_with_delimiter process_stats.gc_info.allocations
  end

  def ar_tooltip
    ar_objs, ar_types = process_stats.activerecord_stats
    rows = ar_types.sort_by do |_, count|
      -count
    end.map do |name, count|
      [count, name]
    end

    count_width = ar_objs.to_s.length

    fmt = "%#{count_width}d | %s"
    rows.map! do |row|
      fmt % row
    end

    width = ar_objs.to_s.length
    ar_info = sprintf("%#{count_width}d | AR objects\n\n%s", ar_objs, rows.join("\n"))
  end

  def query_tooltip
    query_count = GitHub::MysqlInstrumenter.query_count
    query_time = GitHub::MysqlInstrumenter.query_time
    by_cluster = GitHub::MysqlInstrumenter.queries_per_database
    by_cluster = by_cluster.transform_keys { |name| name.safe_constantize.try(:cluster_name) || "(unknown)" }
    by_cluster = by_cluster.sort_by(&:last).reverse
    by_table = GitHub::MysqlInstrumenter.queries_per_table.sort_by(&:last).reverse.first(10)

    query_info = +""
    query_info << "%d queries taking %.2f ms\n" % [query_count, query_time * 1000.0]
    query_info << "Across #{by_cluster.size} clusters:\n  #{by_cluster.map { |n, c| "#{n} (#{c})" }.join("\n  ")}"
    query_info << "\n\nQueries per table (top 10):\n  #{by_table.map { |n, c| "#{n} (#{c})" }.join("\n  ")}"

    query_info
  end

  def sql_tooltip
    "#{query_tooltip}\n\n#{ar_tooltip}"
  end

  def es_loader_stats?
    process_stat_tracked?(:es) && Elastomer::QueryStats.instance.any?
  end

  def es_loader_stats
    stats = Elastomer::QueryStats.instance

    path_width = stats.map(&:url_path).map(&:length).max
    cluster_width = stats.map(&:cluster).map(&:length).max
    rows = stats.map do |stat|
      sprintf("%5s | %5s | %5s | %#{cluster_width}s | %#{path_width}s\n",
        stat.time,
        stat.timed_out,
        stat.total,
        stat.cluster,
        stat.url_path,
      )
    end

    sprintf("%5s | %5s | %5s | %#{cluster_width}s | %#{path_width}s\n%s", "Time", "T-Out", "Hits", "Cluster", "Path", rows.join(""))
  end

  def graphql_loader_stats?
    process_stat_tracked?(:graphql) && Platform::LoaderTracker.loaders.any?
  end

  def graphql_loader_stats
    loaders = Platform::LoaderTracker.loaders

    fetch_count = loaders.values.map(&:length).sum
    fetch_duration_ms = loaders.values.flat_map(&:sum).sum

    width = loaders.values.map(&:length).max.to_s.length

    rows = loaders.sort_by do |(_loader, durations)|
      -durations.length
    end.map do |(loader, durations)|
      sprintf("%#{width}d | %s (%0.2fms)\n", durations.length, loader, durations.sum)
    end

    sprintf("%#{width}d | Batch Loader fetches (%0.2fms)\n\n%s", fetch_count, fetch_duration_ms, rows.join(""))
  end

  def query_cache_hits
    return unless process_stats
    ar_objs, ar_types, hits = process_stats.activerecord_stats
    hits
  end

  def pending_jobs
    number_with_delimiter site_stats[:pending_jobs]
  end

  def pending_jobs_raw
    site_stats[:pending_jobs]
  end

  def job_stats?
    enterprise? || Rails.env.development?
  end

  def gitrpc_call_stats
    call_stats = GitRPCLogSubscriber.rpc_call_stats
    return "" if call_stats.empty?
    rows = call_stats
      .sort_by { |_command, stats| -stats.time }
      .map     { |command, stats| sprintf("%7.3f | %7d | %s\n", stats.time, stats.count, command) }
    sprintf("%7s | %7s | %s\n%s", "Seconds", "Count", "Command", rows.join(""))
  end

  def gitrpc_trace
    _, _, rpc_calls = process_stats.gitrpc_stats

    rpc_calls
  end

  def redis_trace
    _, _, redis_queries = process_stats.redis_stats

    redis_queries
  end

  def exceptions?
    Rails.env.development? && (most_recent_exception > 1.hour.ago)
  end

  def most_recent_exception
    @most_recent_exception ||=
      begin
        stat = File.stat(GitHub.failbot_log_path)
        return Time.at(0) if stat.size == 0
        stat.mtime
      rescue Errno::ENOENT
        Time.at(0)
      end
  end

  def controller_key
    @controller_key ||= request.params[:controller].parameterize
  end

  def action_key
    @action_key ||= request.params[:action].parameterize
  end

  def glb_hosts
    hostnames = process_stats.glb_via.map { |row| row["hostname"] }

    # include the fe/k8s node as the termination point
    hostnames.push(GitHub.local_host_name)

    hostnames.join("\n")
  end

  def glb_regions
    regions = process_stats.glb_via.map { |row| row["region"] }

    # include the k8s cluster name, or unicorn region, as the termination point
    if GitHub.kube?
      regions.push(GitHub.kubernetes_cluster_name || "k8s")
    else
      regions.push(GitHub.server_region)
    end

    # we should never have a region loop, so duplicate regions should be neighboring entries
    # this means the regions list will show each region _change_, rather than each hop's region
    regions = regions.uniq

    safe_join(regions, " \u2192 ")
  end

  def vernier_profile_path
    trace_path(
      flamegraph: 1,
      flamegraph_interval: 250,
      flamegraph_allocation_sample_rate: 200,
      flamegraph_mode: "vernier"
    )
  end

  def auth_tooltip
    <<-MSG
      #{GitHub::AuthzdInstrumenter.authorize_request_count} unbatched
      #{GitHub::AuthzdInstrumenter.batch_authorize_request_count} batched
    MSG
  end

  def auth_summary
    [
      "#{number_with_precision(GitHub::AuthzdInstrumenter.total_request_time, precision: 0)} ms",
      GitHub::AuthzdInstrumenter.authorize_request_count,
      GitHub::AuthzdInstrumenter.batch_authorize_request_count
    ].join(" / ")
  end

  def any_authz_stats?
    GitHub::AuthzdInstrumenter.any?
  end

  def authzd_authorize_requests
    GitHub::AuthzdInstrumenter.authorize_requests
  end

  def authzd_batch_authorize_requests
    GitHub::AuthzdInstrumenter.batch_authorize_requests
  end

  def cache_tracer_enabled?
    GitHub::Cache::Client.track_events
  end

  def cache_events
    GitHub::Cache::Client.query_events.each do |event|
      event[:slow] = event[:latency] / GitHub::Cache::Client.query_time >= 0.10
    end
  end

  def cache_event_formatted_stack_locations(event)
    event[:locations].map do |location|
      GitHub::FormattedStackLocation.from_location(location)
    end.reject do |location|
      location.description.starts_with? "gem"
    end
  end

  def cache_event_formatted_latency(event)
    "%0.3f" % (event[:latency] * 1000)
  end

  def cache_key_utf8_safe(key)
    key.dup.force_encoding(Encoding::UTF_8).scrub!
  end

  def markdown_call_stats
    call_stats = T.unsafe(GitHub::Goomba::WarpPipeStats).call_stats
    return "" if call_stats.empty?

    rows = call_stats
      .filter  { |stats| stats.time >= 0.1 }
      .sort_by { |stats| -stats.time }
      .map     { |stats| sprintf("%7.1f | %7d | %s\n", stats.time, stats.count, stats.label) }
    sprintf("%7s | %7s | %s\n\n%s", "ms", "Count", "Operation", rows.join(""))
  end

  def cluster_details_label(bucketed_clusters)
    "Queries against required clusters: #{bucketed_clusters[:required].length}\n" +
      "Queries against optional clusters: #{bucketed_clusters[:optional].length}\n" +
      "Queries against undeclared clusters: #{bucketed_clusters[:undeclared].length}"
  end

  memoize def disabled_cluster_names
    Thread.current.fetch(GitHub::DatabaseQueryDisabler::DISABLE_KEY, []).map(&:name)
  end

  def bucket_clusters(required_clusters:, optional_clusters:)
    by_cluster = GitHub::MysqlInstrumenter.queries_per_database

    required_cluster_names = (required_clusters || []).map(&:name)
    optional_cluster_names = (optional_clusters || []).map(&:name)

    required = {}
    optional = {}
    undeclared = {}

    disabled_cluster_names.each do |name|
      if required_cluster_names.include?(name)
        required[name] = 0
      elsif optional_cluster_names.include?(name)
        optional[name] = 0
      else
        undeclared[name] = 0
      end
    end

    by_cluster.each_with_object({ required:, optional:, undeclared: }) do |(cluster, count), memo|
      if required_cluster_names.include?(cluster)
        memo[:required][cluster] = count
      elsif optional_cluster_names.include?(cluster)
        memo[:optional][cluster] = count
      else
        memo[:undeclared][cluster] = count
      end
    end
  end

  def api_insights_pane_path
    trace_path(_tracing: "true")
  end

  def cache_tracer_path
    trace_path(
      cache_tracer: 1
    )
  end

  def ff_cache_tracer_path
    trace_path(
      ff_cache_tracer: 1
    )
  end

  def graphql_tracer_path
    trace_path(
      graphql_query_trace: true,
      xhr_stats: xhr_stats
    )
  end

  def mysql_tracer_path
    trace_path(
      mysql_query_trace: true,
      xhr_stats: xhr_stats
    )
  end

  private

  def trace_path(append_params)
    url = request.url

    # for voltron-based url, extract the url from the context to have the canonical url
    # as set in app/controllers/voltron/fragment_controller.rb#add_voltron_original_url_to_context
    # instead of the voltron-based url (for example "_view_fragments/issues/show/monalisa/illuminati/1/issue_layout")
    if GitHub.context[:controller] && GitHub.context[:controller].starts_with?("voltron") && GitHub.context[:url]
      url = GitHub.context[:url]
    end

    uri = URI.parse(url)
    params = URI::decode_www_form(uri.query || "").to_h

    # Remove any existing tracers
    params.delete("cache_tracer")
    params.delete("ff_cache_tracer")
    params.delete("graphql_query_trace")
    params.delete("mysql_query_trace")

    params.merge!(append_params)

    uri.query = URI::encode_www_form(params)
    uri.to_s
  end

  def kube_backend?(hostname)
    # Kubernetes Pods have a hostname set to the pod name, which should
    # match this (potentially fragile) regex
    hostname =~ /\A[\w-]+-\d+-[0-9a-z]+\Z/ && GitHub.kube?
  end

  def format_time(time)
    time = time * 1000
    if time >= 1000
      "%.1fs" % (time / 1000)
    else
      "%.0fms" % time
    end
  end
end
