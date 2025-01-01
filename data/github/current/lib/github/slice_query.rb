# typed: false
# frozen_string_literal: true

# Mixin for slicing up work
#
# Some queries take too long, even after multiple rounds of
# optimizations, to complete within the SQL query timeout.  Here is
# some machinery to assist with slicing them up.
#
# Call +get_query_slice+ with the name of the operation you want to
# slice, then call +get_contiguous_id_range+ with the result to get
# the offsets of the ids to use for the next query.
#
# After performing the operation on the returned rows, call
# +put_adjusted_query_slice+ with the same name as +get_query_slice+
# to store the data for the next iteration.
#
# +put_adjusted_query_slice+ will take care of wrapping around once
# the end of the table is reached.
#
# We aim to have each operation take between 3 and 5 seconds and the
# slices will adjust accordingly. The state is kept in Redis.
#
#    start_time, offset, slices = get_query_slice("bad-replica-counts")
#    offset, next_offset = get_contiguous_id_range("repository_networks", ApplicationRecord::Domain::Repositories, offset, slices)
#    do_sql_query()
#    put_adjusted_query_slice("bad-replica-counts", start_time, offset, next_offset, slices)
#
#
# There's also the facility to detect whether we've looped over a table once
# already in a given day.  Use +rate_limited?+ as follows:
#
#    start_time, offset, slices = get_query_slice("bad-replica-counts")
#    offset, next_offset = get_contiguous_id_range("repository_networks", ApplicationRecord::Domain::Repositories, offset, slices)
#    if rate_limited?("repository_networks", offset)
#      # we've already completed repository_networks for today
#    else
#      do_sql_query()
#      put_adjusted_query_slice("bad-replica-counts", start_time, offset, next_offset, slices)
#    end
#
# Include in a model/class that defines the following methods:
#
# * query_namespace - the general area of the code

require "scientist"

module SliceQuery
  include GitHub::RateLimitable
  include Scientist

  QUERY_TOO_FAST = 3  # seconds
  QUERY_TOO_SLOW = 5  # seconds
  DEFAULT_SLICES = 100
  ROWS_PER_SLICE = 10000 # Step size for time adjustment
  CACHE_EXPIRES = 2.weeks

  # We want to include the constants as well as add our method as
  # class methods, so when we're included, do both include and extend.
  def self.included(base)
    base.extend(self)
  end

  # Get the next slice for the operation +key+
  def get_query_slice(key)
    offset = get_offset_value(key)
    slices = get_slices_value(key)

    unless Rails.env.development?
      GitHub.logger.info("fetched query slice",
                         "code.function" => "get_query_slice",
                         "gh.slice_query.key" => key,
                         "gh.slice_query.offset" => offset,
                         "gh.slice.num_slices" => slices)
    end
    [Time.now, offset, slices]
  end

  def get_offset_value(key)
    offset = GitHub.kv.get(get_offset_cache_key(key)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    if offset
      offset.to_i
    else
      (Rails.env.test? ? 0 : rand(10_000_000))
    end
  end

  def get_slices_value(key)
    offset = GitHub.kv.get(get_slices_cache_key(key)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    if offset
      offset.to_i
    else
      (Rails.env.test? ? 1000 : DEFAULT_SLICES)
    end
  end

  def put_query_slice(key, offset, slices)
    ActiveRecord::Base.connected_to(role: :writing) do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set(get_offset_cache_key(key), offset.to_s, expires: CACHE_EXPIRES.from_now)
      # rubocop:enable GitHub/DoNotUseGlobalKv
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set(get_slices_cache_key(key), slices.to_s, expires: CACHE_EXPIRES.from_now)
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end

  def get_offset_cache_key(key)
    "#{query_namespace}:query-slice:#{key}:offset"
  end

  def get_slices_cache_key(key)
    "#{query_namespace}:query-slice:#{key}:slices"
  end

  def calculate_adjusted_query_slice(elapsed, rss, offset, next_offset, slices)
    # wrap to zero if we got fewer than expected
    next_offset = 0 if next_offset - offset < slices * ROWS_PER_SLICE

    if slices < 1000 && elapsed < QUERY_TOO_FAST && rss_ok?(rss)
      slices += 1
    elsif slices > 1 && !rss_ok?(rss)
      slices = prorate_slices_by_rss(slices, **rss)
    elsif slices > 1 && elapsed > QUERY_TOO_SLOW
      slices -= 1
    end

    { next_offset: next_offset, slices: slices }
  end

  def rss_ok?(rss)
    return true if rss.nil?
    rss[:max].to_i < rss[:config_max].to_i
  end

  def prorate_slices_by_rss(slices, config_max:, start:, max:)
    return 1 if config_max < start # config_max is apparently too low!
    rss_diff = max - start
    target_rss_diff = config_max - start
    new_slices = (slices * target_rss_diff / rss_diff) - 1
    [1, new_slices].max
  end

  def put_adjusted_query_slice(key, start_time, offset, next_offset, slices, no_adjustment: false, max_query_time: nil, rss: nil)
    if no_adjustment
      adjusted = { next_offset: next_offset, slices: slices }
    else
      max_query_time ||= Time.now - start_time
      adjusted = calculate_adjusted_query_slice(max_query_time, rss, offset, next_offset, slices)
    end

    GitHub.dogstats.gauge("query-slices.offset".freeze, adjusted[:next_offset],
                          tags: ["namespace:#{query_namespace}", "key:#{key}"])
    GitHub.dogstats.gauge("query-slices.slices".freeze, adjusted[:slices],
                          tags: ["namespace:#{query_namespace}", "key:#{key}"])
    put_query_slice(key, adjusted[:next_offset], adjusted[:slices])
  end

  def get_contiguous_id_range(table, domain_class, offset, slices)
    limit = slices * ROWS_PER_SLICE
    bindings = {
      table: Arel.sql(table.to_s),
      offset: offset,
      limit: Arel.sql(limit.to_s)
    }
    sql = Arel.sql("SELECT MAX(sub.id) FROM (SELECT id FROM :table WHERE id>:offset ORDER BY id LIMIT :limit) sub", **bindings)
    results = domain_class.connection.select_rows(sql)
    if !results.empty? && !results.first.first.nil?
      [offset, results.first.first]
    elsif offset != 0
      get_contiguous_id_range(table, domain_class, 0, limit)
    else
      # If we get here, the table is empty, or our query failed in a
      # way that looked like an empty table.  An exception would
      # appropriate, except that the unit tests actually hit this
      # case.  [ 0, 0 ] is also appropriate here.
      [0, 0]
    end
  end

  def rate_limited?(key, offset, ttl: 24 * 60 * 60)
    return false if offset != 0

    limit_key = "#{query_namespace}:query-slice:#{key}"
    rate_limit_increment(limit_key, { max_tries: 2, ttl: ttl }).at_limit?
  end

  def block_with_timeout(key, &block)
    begin
      block.call
    rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout => ex
      _, offset, slices = get_query_slice(key)

      raise if slices == 1

      put_query_slice(key, offset, slices / 2)
      nil
    end
  end

  # `ps` shows RSS in KB. Convert it to B.
  def self.rss_bytes
    1024 * Progeny::Command.new("ps", "o", "rss=", Process.pid.to_s).out.to_i
  end

  class Slice
    include SliceQuery

    def initialize(slice_name:, id_table:, domain_class:, query_namespace:, max_rss: nil)
      @slice_name = slice_name
      @id_table = id_table
      @domain_class = domain_class
      @query_namespace = query_namespace
      @start_time, @offset, @slices = get_query_slice(@slice_name)
      @offset, @next_offset = get_contiguous_id_range(@id_table, @domain_class, @offset, @slices)
      @query_times = []
      @max_rss = max_rss
      @rss_values = [SliceQuery.rss_bytes] if max_rss
    end

    attr_reader :offset, :next_offset, :query_namespace, :domain_class

    def querying
      start = Time.now
      result = block_with_timeout(@slice_name) { yield }
      @rss_values << SliceQuery.rss_bytes if @rss_values
      if result
        @query_times.push(Time.now - start)
      end
      result
    end

    def set_next_offset(next_offset)
      put_adjusted_query_slice(@slice_name, @start_time, @offset, next_offset, @slices, no_adjustment: true)
    end

    def move_to_next_offset
      max_query_time = @query_times.max
      rss = nil
      if @rss_values && @max_rss
        rss = { config_max: @max_rss, start: @rss_values.first, max: @rss_values.max }
      end
      put_adjusted_query_slice(@slice_name, @start_time, @offset, @next_offset, @slices, max_query_time: max_query_time, rss: rss)
    end
  end

  class OneIdSlice
    attr_reader :domain_class

    def initialize(id, domain_class)
      @id = id
      @domain_class = domain_class
    end

    def offset
      @id - 1
    end

    def next_offset
      @id
    end

    def querying
      yield
    end

    def set_next_offset(*)
    end

    def move_to_next_offset(*)
    end
  end
end
