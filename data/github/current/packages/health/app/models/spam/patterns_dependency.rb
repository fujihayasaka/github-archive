# typed: true
# frozen_string_literal: true

module Spam::PatternsDependency

  def current_pattern_base_key
    "spam_current_patterns_"
  end

  def actual_key(key)
    current_pattern_base_key + key
  end

  def current_pattern_queue_for(key)
    Spam::Queue.new actual_key(key)
  end

  # where key is like 'filename' or 'data'
  def add_current_pattern(key, pattern)
    if cpq = current_pattern_queue_for(key)
      cpq.push pattern.to_s
    end
  end

  # where key is like 'filename' or 'data'
  def remove_current_pattern(key, pattern)
    if cpq = current_pattern_queue_for(key)
      cpq.drop_this pattern.to_s
    end
  end

  # where key is like 'filename' or 'data'
  def get_current_patterns(key)
    if cpq = current_pattern_queue_for(key)
      cpq.peek cpq.size
    end
  end

  def get_current_regexps(key)
    get_current_patterns(key).map { |t| Regexp.new(t) }
  end

  def each_current_pattern(key)
    get_current_regexps(key).each do |regexp|
      yield regexp
    end
  end

end
