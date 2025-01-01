# typed: true
# frozen_string_literal: true

# Internal: A thread-local cache and Rack middleware for Experiment instances.
class ExperimentCache
  def initialize(app)
    @app = app
  end

  def call(env)
    ExperimentCache.enable { @app.call(env) }
  end

  def self.clear
    data.clear
  end

  def self.fetch(key, &block)
    return yield if !enabled?

    value = data[key]
    if data.key?(key)
      GitHub.dogstats.increment("cache.hit", tags: ["action:experiment.fetch"])
      return value
    end

    GitHub.dogstats.increment("cache.miss", tags: ["action:experiment.fetch"])
    data[key] = yield
  end

  def self.enable(&block)
    clear
    self.enabled = true
    yield
  ensure
    self.enabled = false
    clear
  end

  def self.data
    Thread.current[:experiment_cache_data] ||= {}
  end
  private_class_method :data

  def self.enabled?
    Thread.current[:experiment_cache_enabled] || false
  end
  private_class_method :enabled?

  def self.enabled=(flag)
    Thread.current[:experiment_cache_enabled] = flag
  end
  private_class_method :enabled=
end
