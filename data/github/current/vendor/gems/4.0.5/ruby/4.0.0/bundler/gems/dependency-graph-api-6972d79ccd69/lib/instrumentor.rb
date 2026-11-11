# frozen_string_literal: true
class Instrumentor
  def initialize(stats = Rails.application.stats)
    @stats = stats
  end

  def count(name, count, **payload)
    tags = hash_to_tags(payload)
    stats.count(name, count, tags: tags)
  end

  def histogram(name, value, **payload)
    tags = hash_to_tags(payload)
    stats.histogram(name, value, tags: tags)
  end

  def increment(name, **payload)
    tags = hash_to_tags(payload)
    stats.increment(name, tags: tags)
  end

  def time(name, **payload, &block)
    tags = hash_to_tags(payload)
    stats.time(name, tags: tags, &block)
  end

  def timing(name, value, **payload)
    tags = hash_to_tags(payload)
    stats.timing(name, value, tags: tags)
  end

  def distribution(name, value, **payload)
    tags = hash_to_tags(payload)
    stats.distribution(name, value, tags: tags)
  end

  def time_dist(name, **payload)
    return unless block_given?
    t_start = Time.now
    yield
  ensure
    t_end = Time.now
    duration = (t_end - t_start).in_milliseconds
    distribution(name, duration, **payload)
  end

  private

  attr_accessor :stats

  def hash_to_tags(hash)
    hash.map { |k, v| [k, v].join(":") }
  end
end
