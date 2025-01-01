# typed: true
# frozen_string_literal: true

module GitHub
  class DebugDogstatsD < NullDogstatsD
    def increment(stat, opts = {})
      warn "DATADOG: increment #{stat} #{opts.inspect}"
      super
    end

    def decrement(stat, opts = {})
      warn "DATADOG: decrement #{stat} #{opts.inspect}"
    end

    def count(stat, count, opts = {})
      warn "DATADOG: count #{stat} #{count} #{opts.inspect}"
      super
    end

    def gauge(stat, value, opts = {})
      warn "DATADOG: gauge #{stat} #{value} #{opts.inspect}"
      super
    end

    def histogram(stat, value, opts = {})
      warn "DATADOG: histogram #{stat} #{value} #{opts.inspect}"
      super
    end

    def distribution(stat, value, opts = {})
      warn "DATADOG: distribution #{stat} #{value} #{opts.inspect}"
      super
    end

    def timing(stat, ms, opts = {})
      warn "DATADOG: timing #{stat} #{ms} #{opts.inspect}"
      super
    end

    def time(stat, opts = {})
      warn "DATADOG: time #{stat} #{opts.inspect}"
      super
    end
  end
end
