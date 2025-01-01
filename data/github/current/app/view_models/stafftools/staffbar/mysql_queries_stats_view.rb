# typed: true
# frozen_string_literal: true

class Stafftools::Staffbar::MysqlQueriesStatsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :tags, :html_id, :controller

  def query_count
    queries.count
  end

  def primary_query_count
    queries.count(&:on_primary)
  end

  def queries_per_database
    @queries_per_database ||= GitHub::MysqlInstrumenter.queries_per_database
  end

  def cached_query_count
    cache_hits.count
  end

  def query_time
    queries.map(&:duration).inject(0, &:+)
  end

  def digest_count
    digest_stats.size
  end

  def row_count
    digest_stats.map { |_digest, stats| stats[:results] }.inject(0, &:+)
  end

  def cached_row_count
    cached_digest_stats.map { |_digest, stats| stats[:results] }.inject(0, &:+)
  end

  def similar_queries_count(query)
    uncached_stats = digest_stats.fetch(query.digested_sql, {})
    cached_stats = cached_digest_stats.fetch(query.digested_sql, {})
    uncached_stats[:count].to_i + cached_stats[:count].to_i
  end

  def loader_tag(query)
    query.tags.select { |tag| tag.to_s.starts_with?("loader:") }.join(";")
  end

  def digest_stats
    @digest_stats ||= compute_digest_stats(queries).freeze
  end

  def sorted_digest_stats
    @sorted_digest_stats ||= digest_stats.sort_by { |_digest, stats| -stats[:count] }.freeze
  end

  def cached_digest_stats
    @cached_digest_stats ||= compute_digest_stats(cache_hits).freeze
  end

  def sorted_cached_digest_stats
    @sorted_cached_digest_stats ||= cached_digest_stats.sort_by { |_digest, stats| -stats[:results] }.freeze
  end

  def colorized_queries
    @colorized_queries ||= begin
      sanitized_queries = sorted_queries.map do |query|
        query.sql.dup.force_encoding("utf-8").squish.scrub!
      end
      highlighted = GitHub::Colorize.highlight_many(Array.new(sanitized_queries.size, "source.sql"), sanitized_queries)
      highlighted.empty? ? sanitized_queries.map { |l| Array(l) } : highlighted
    end
  end

  def sorted_queries
    @sorted_queries ||= begin
      combined = queries + cache_hits
      combined.sort_by { |q| -(q.duration || 0) }.freeze
    end
  end

  def time_class(query)
    case
    when query.duration.nil?
      "lightskyblue"
    when query.duration > 0.100
      "red"
    when query.duration > 0.050
      "palegoldenrod"
    when query.duration > 0.010
      "goldenrod"
    when query.duration > 0.001
      "mediumpurple"
    else
      "grey"
    end
  end

  def n_plus1_queries
    @_n_plus1_queries ||= begin
      grouped_queries = queries.group_by do |query|
        [query.backtrace.join(""), query.digested_sql]
      end.values.select { |values| values.size > 1 }
    end
  end

  def by_callstack_queries
    @_by_callstack_queries ||= begin
      # Group by file and sort by number of queries
      grouped_queries = queries.group_by do |query|
        query.backtrace.find { |f| f.to_s =~ /app\/(controllers|models|components|views)\// }&.absolute_path
      end.sort_by { |_, values| -values.size }

      grouped_queries.each do |_, group|
        group.sort_by! { |q| -(q.duration || 0) }
      end
    end
  end

  def dependency_level(cluster_class)
    if cluster_class.is_a?(Class)
      cluster_class = cluster_class.name
    end

    if required_clusters.include?(cluster_class)
      "required"
    elsif optional_clusters.include?(cluster_class)
      "optional"
    else
      "undeclared"
    end
  end

  def required_clusters
    @_required_clusters ||= controller.required_clusters.map(&:name).to_set
  end

  def optional_clusters
    @_optional_clusters ||= controller.optional_clusters.map(&:name).to_set
  end

  def fallbacks(query)
    prefix = "fallback:"
    query.tags.flatten
      .filter { |tag| tag.start_with?(prefix) }
      .map { |tag| tag.sub(prefix, "") }
      .sort
  end

  private

  def queries
    @queries ||= filter_queries_by_tags(GitHub::MysqlInstrumenter.queries).freeze
  end

  def cache_hits
    @cache_hits ||= filter_queries_by_tags(QueryCacheLogSubscriber.cache_hits).freeze
  end

  def compute_digest_stats(queries)
    queries.each_with_object({}) do |query, hash|
      stats = hash.fetch(query.digested_sql) do |digest|
        hash[digest] = { count: 0, time: 0, results: 0 }
      end
      stats[:count] += 1
      stats[:time] += query.duration || 0
      stats[:results] += query.result_count || 0
    end
  end

  def filter_queries_by_tags(queries)
    return queries.dup unless tags.present?

    queries.select { |query| (tags & query.tags) == tags }
  end
end
