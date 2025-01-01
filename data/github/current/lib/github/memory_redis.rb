# typed: true
# frozen_string_literal: true

module GitHub
  class MemoryRedis
    def initialize
      @data = {}
      @ttl = {}
      @pipeline_active = false
      @pipeline_results = []
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

    def set(key, value, ex: nil, keepttl: nil)
      @data[key] = value

      if ex
        @ttl[key] = Time.now + ex
      end

      @pipeline_results << "OK" if @pipeline_active
      "OK"
    end

    def del(key)
      deleted = @data.key?(key) ? 1 : 0
      @data.delete(key)
      @ttl.delete(key)

      @pipeline_results << deleted if @pipeline_active
      deleted
    end

    def unlink(key)
      del(key)
    end

    def clear
      @data.clear
      @ttl.clear
    end
  end
end
