# typed: true
# frozen_string_literal: true

module GitHub
  class MemoryRedis
    attr_accessor :read_timeout

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
