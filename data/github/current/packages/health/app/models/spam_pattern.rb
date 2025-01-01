# typed: false
# frozen_string_literal: true

class SpamPattern < ApplicationRecord::Domain::Spam
  include GitHub::Validations
  DEFAULT_TEST_RECORD_COUNT = 15
  VALID_CLASS_NAMES = %w{Issue IssueComment Gist GistComment Profile PullRequest Repository User}

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # SpamPattern.for(User) =>
  #     SpamPattern.where(class_name: 'User')
  scope :for, -> (class_name) { where(class_name: class_name.to_s) }

  scope :last_ip_patterns, -> { where(class_name: "User", attribute_name: "last_ip") }

  validates_presence_of :attribute_name
  validates_presence_of :class_name
  validates_presence_of :pattern

  validates_uniqueness_of :pattern, scope: [:class_name, :attribute_name], case_sensitive: false
  validates :comment, unicode3: true

  # Public: Build and return regex that is a union of all the SpamPattern last_ip regexes. Used in
  # the GitHub Platform to optimize last_ip pattern matching. Also optimized by avoiding AR object
  # instantiation.
  #
  # Returns a Regexp.
  def self.last_ip_patterns_regexp
    Regexp.union last_ip_patterns.pluck(:pattern).map { |pattern| Regexp.new(pattern) }
  end

  def self.matches_for(target)
    SpamPattern.for(target.class).select { |sp| sp.matches?(target) }
  end

  # Public: Return matches for target that can flag as spam
  def self.flag_matches_for(target)
    matches_for(target).select { |sp| sp.flag? }
  end

  # Public: Load all active patterns for the given class
  #
  # class_name - This can be a class `User` or a class name as a
  #              string.
  #
  # Returns an Array of SpamPatterns (not an AR scope)
  def self.active_for(class_name)
    active.for(class_name).to_a
  end

  # Public: Find the active patterns for the given class_name.
  #
  # NOTE: We memoize them for a TTL of GitHub.spam_pattern_memoization_ttl_in_seconds
  #       to ensure we don't repeatedly load them over and over in workers.
  #
  #       In non production environments this value defaults to 0.
  #
  # Returns an Array of SpamPattern records.
  def self.memoized_active_for(klass)
    return [] if klass.blank?

    # Ensure the hash key and stat key are lower case/uniform
    class_key = klass.to_s.parameterize

    GitHub.dogstats.increment "spam.memoized_patterns", tags: ["pattern_action:try", "class:#{class_key}"]

    memo_ttl = GitHub.spam_pattern_memoization_ttl_in_seconds
    return self.active_for(klass) if memo_ttl == 0

    @memoized_patterns ||= Hash.new { |h, k| h[k] = [] }
    cached_at, patterns = @memoized_patterns[class_key]

    current_time = Time.now.to_i

    if cached_at.nil? || cached_at + memo_ttl <= current_time
      patterns = self.active_for(klass)
      @memoized_patterns[class_key] = [current_time, patterns]
      stat_type = cached_at.nil? ? "miss" : "expired"
      GitHub.dogstats.increment "spam.memoized_patterns", tags: ["pattern_action:#{stat_type}", "class:#{class_key}"]
    else
      GitHub.dogstats.increment "spam.memoized_patterns", tags: ["pattern_action:hit", "class:#{class_key}"]
    end

    patterns
  end

  # Public: Used for forced clearing of cache
  #
  # In testing we need to clear the cache explicitly because we Time
  # travel quite a bit and change the TTL at runtime.
  def self.clear_memoized_active_for
    remove_instance_variable :@memoized_patterns if defined?(@memoized_patterns)
  end

  def attribute_name=(value)
    super value.to_s
  end

  def class_name=(value)
    super value.to_s
  end

  def pattern=(value)
    super value.to_s
  end

  # Public: Does this SpamPattern match the given candidate?
  #
  # We differeniate behavior based on the pattern type.  If it's JSON
  # we use Spam::Conditional, else we use a Regexp attribute match.
  def matches?(candidate)
    GitHub.dogstats.increment "spam.patterns.pattern_#{id}", tags: ["pattern_action:evaluation", "target_class:#{class_name}", "target_attribute:#{attribute_name}"]

    start_time = GitHub::Dogstats.monotonic_time

    # If this is a newer JSON pattern, pass it to Spam::Conditional
    # for match analysis
    match = if pattern =~ /\A\s*{/
      conditional = Spam::Conditional.new pattern
      conditional.matches? candidate
    else
      # otherwise, use the older Regexp-only match
      attributes_match candidate
    end
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("spam.patterns.pattern_#{id}.dist.time", elapsed, tags: ["target_class:#{class_name}", "target_attribute:#{attribute_name}"])
    match
  end

  def attributes_match(candidate)
    return nil unless is_compatible?(candidate)
    if has_actual_attribute?(candidate)
      regexp =~ candidate.attributes[attribute_name]
    elsif candidate.respond_to? attribute_name
      regexp =~ candidate.send(attribute_name)
    end
  end

  # Return true if this is an actual attribute belonging to candidate's
  # class, not just a method to which candidate will respond.
  # Return false otherwise.
  def has_actual_attribute?(candidate)
    candidate.respond_to?(:attributes) &&
      candidate.attributes.include?(attribute_name)
  end

  def is_compatible?(candidate)
    candidate.is_a? self.class_name.constantize
  end

  def =~(target)
    regexp =~ target
  end

  def disable!
    self.update_attribute :active, false if self.active?
  end

  def enable!
    self.update_attribute :active, true unless self.active?
  end

  def regexp
    @regexp ||= Regexp.new(pattern)
  end

  # This metric tracks the percentage of matches that are found to be
  # false positives.
  def false_positive_percentage
    (false_positives.to_f / match_count.to_f) * 100
  end

  def record_false_positive!
    GitHub.dogstats.increment "spam.patterns.pattern_#{id}", tags: ["pattern_action:false_positive", "target_class:#{class_name}", "target_attribute:#{attribute_name}"]
    self.false_positives += 1
    self.match_count -= 1 if self.match_count > 0
    self.last_false_positive_at = Time.now
    save
  end

  def record_match!
    GitHub.dogstats.increment "spam.patterns.pattern_#{id}", tags: ["pattern_action:match", "target_class:#{class_name}", "target_attribute:#{attribute_name}"]
    self.match_count += 1
    self.last_matched_at = Time.now
    save
  end

  # Public: Test records for UI based testing
  #
  # This is a simplified version of where we are headed
  # down the road.
  def test_records(record_count: DEFAULT_TEST_RECORD_COUNT)
    self.class_name.constantize.last(record_count)
  end
end
