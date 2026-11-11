# typed: true
# frozen_string_literal: true

module GitHub
  # Public: Lightweight in-memory Redis replacement for exercising Redis-backed
  # behavior in test suites without starting an external service. Callers map
  # their logical Redis connections (for example, `:remote_cache`) to isolated
  # in-memory instances via {.create}. Test helpers call {.reset} before every
  # example, so each run starts from a blank registry unless explicitly reused
  # within the same test.
  class MemoryRedis
    attr_accessor :read_timeout

    @registry = T.let({}, T::Hash[Symbol, GitHub::MemoryRedis])

    # Public: Retrieve a cached in-memory Redis instance for use in tests.
    #
    # @param identifier [Symbol] Scoped key representing the logical Redis
    #   connection (for example, `:remote_cache`). Selecting the same identifier
    #   returns the same in-memory instance, while using a different identifier
    #   yields an isolated store. The test harness invokes {.reset} prior to
    #   each example, so identifiers can be safely reused across tests without
    #   leaking state.
    # @return [GitHub::MemoryRedis] In-memory Redis stub scoped to the
    #   identifier.
    #
    def self.create(identifier:)
      @registry[identifier] ||= GitHub::MemoryRedis.new
    end

    def self.reset
      @registry = {}
    end

    def initialize
      @data = {}
      @ttl = {}
      @pipeline_active = false
      @pipeline_results = []
    end

    def _client
      self
    end

    def connected?
      true
    end

    def ping
      @pipeline_results << true if @pipeline_active
      true
    end

    def get(key)
      @pipeline_results << @data[key] if @pipeline_active
      @data[key]
    end

    def mget(*keys)
      keys.map { |key| get(key) }
    end

    def pipelined
      @pipeline_active = true
      @pipeline_results = []
      yield self
      @pipeline_results
    ensure
      @pipeline_active = false
    end

    def set(key, value, ex: nil, keepttl: nil, nx: nil, xx: nil)
      # NX -- Only set the key if it does not already exist.
      # XX -- Only set the key if it already exists.
      if nx && @data.key?(key)
        @pipeline_results << nil if @pipeline_active
        return nil
      end

      if xx && !@data.key?(key)
        @pipeline_results << nil if @pipeline_active
        return nil
      end

      @data[key] = value

      if ex
        @ttl[key] = ex
      end

      @pipeline_results << "OK" if @pipeline_active
      "OK"
    end

    def setex(key, ttl, value)
      set(key, value, ex: ttl)
    end

    def del(*keys)
      deleted = keys.count { |key| @data.key?(key) }
      keys.each do |key|
        @data.delete(key)
        @ttl.delete(key)
      end

      @pipeline_results << deleted if @pipeline_active
      deleted
    end

    def unlink(*keys)
      T.unsafe(self).del(*keys)
    end

    def ttl(key)
      @ttl[key]
    end

    def exists?(key)
      @data.key?(key)
    end

    def keys(pattern = "*")
      # Simple pattern matching - only support "*" for now
      if pattern == "*"
        @data.keys
      else
        # Convert Redis glob pattern to Ruby regex
        regex_pattern = pattern.gsub("*", ".*")
        regex = Regexp.new("\\A#{regex_pattern}\\z")
        @data.keys.select { |k| k.match?(regex) }
      end
    end

    def clear
      @data.clear
      @ttl.clear
    end
  end
end
