# typed: false
# frozen_string_literal: true

# Public: The entry point to the dark tunnel into our anti-spam
# system.  This organizational module isn't intended for inclusion in
# other modules or classes, but rather provies a namespace for a
# pseudo-API.

require_relative "spam/kv"

module Spam
  extend Spam::ClustersDependency
  include Spam::ErrorsDependency
  extend Spam::IpDependency
  extend Spam::PatternsDependency
  extend Spam::QueueDependency

  EXTERNAL_SPAMURAI_BASE_URL = "https://spamurai-next.githubapp.com"

  def self.url_for_account_id(id)
    "#{EXTERNAL_SPAMURAI_BASE_URL}/accounts/#{id}"
  end

  def self.url_for_account_login_ids(ids)
    "#{EXTERNAL_SPAMURAI_BASE_URL}/lookup/id?v=#{ids.join(',')}"
  end

  def self.url_for_account_login(login)
    "#{EXTERNAL_SPAMURAI_BASE_URL}/u/#{login}"
  end

  def self.url_for_trust_safety_account_login(login)
    "#{EXTERNAL_SPAMURAI_BASE_URL}/ts/u/#{login}"
  end

  def self.url_for_repo(login, repo_name)
    "#{EXTERNAL_SPAMURAI_BASE_URL}/r/#{login}/#{repo_name}"
  end

  SENIOR_ANALYST_LOGIN = "erebor"

  HAM     = 0
  SPAM    = 1
  UNKNOWN = -1

  LABELS = [HAM, SPAM, UNKNOWN]

  ALIASES = {
    "ham"     =>  HAM,
    "spam"    =>  SPAM,
    "unknown" =>  UNKNOWN,
  }

  # Note: Not sure if this is the right place to put this?
  LAST_SEEN_USER_CURSOR_KEY = "spam_last_seen_user_cursor"

  # Internal: Given a String, Symbol, or numeric `label`, return the
  # matching `Spam::LABELS` member, transforming strings and symbols
  # via `Spam::ALIASES`. Raises `Spam::ErrorsDependency::BadLabel` if the label is
  # invalid.
  def self.normalize(label)
    candidate = ALIASES[label.to_s.downcase] || label

    unless LABELS.include? candidate
      raise Spam::ErrorsDependency::BadLabel.new label
    end

    candidate
  end

  SPAM_PATTERN_CHECKING = "spam_pattern_checking_enabled"

  def self.spam_pattern_checking_enabled?
    "enabled" == Spam::Kv.store.get(SPAM_PATTERN_CHECKING).value!
  end

  # Set the key in GitHub::KV to enable SpamPattern checks.
  def self.enable_spam_pattern_checking(user = nil)
    message = "SpamPattern checking *enabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
    Spam::Kv.store.set(SPAM_PATTERN_CHECKING, "enabled")
  end

  # Set the key in GitHub::KV to disable SpamPattern checks.
  def self.disable_spam_pattern_checking(user = nil)
    message = "SpamPattern checking *disabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
    Spam::Kv.store.set(SPAM_PATTERN_CHECKING, "disabled")
  end

  def self.stats_time(key, options = {}, &block)
    GitHub.dogstats.time("spam.#{key}", options, &block)
  end

  def self.stats_timing(key, value, options = {})
    GitHub.dogstats.distribution("spam.#{key}", value, options)
  end

  def self.stats_increment(key, options = {})
    GitHub.dogstats.increment("spam.#{key}", options)
  end

  BAYES_NOTIFICATIONS                = "enable_spam_bayes_notifications"
  BAYES_CHECKING                     = "enable_spam_bayes_checking"
  BAYES_COMMENT_CONFIDENCE_THRESHOLD = "bayes_comment_confidence_threshold"
  BAYES_GIST_CONFIDENCE_THRESHOLD    = "bayes_gist_confidence_threshold"
  USE_SPAMURAI                       = "use_spamurai"

  # Returns `true` if chat notifications of Bayes results are enabled.
  # Returns `false` if they are disabled.
  #
  def self.bayes_notifications_enabled?
    "enabled" == Spam::Kv.store.get(BAYES_NOTIFICATIONS).value!
  end

  # Enable Bayes-related notifications.
  def self.enable_bayes_notifications(user = nil)
    Spam::Kv.store.set(BAYES_NOTIFICATIONS, "enabled")
    message = "Bayes notifications *enabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  # Disable Bayes-related notifications.
  def self.disable_bayes_notifications(user = nil)
    Spam::Kv.store.set(BAYES_NOTIFICATIONS, "disabled")
    message = "Bayes notifications *disabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  def self.bayes_checking_enabled?
    "enabled" == Spam::Kv.store.get(BAYES_CHECKING).value!
  end

  # Enable Bayesian spam checks.
  def self.enable_bayes_checking(user = nil)
    Spam::Kv.store.set(BAYES_CHECKING, "enabled")
    message = "Bayesian classifier *enabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  # Disable Bayesian spam checks.
  def self.disable_bayes_checking(user = nil)
    Spam::Kv.store.set(BAYES_CHECKING, "disabled")
    message = "Bayesian classifier *disabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  def self.spamurai_enabled?
    "enabled" == Spam::Kv.store.get(USE_SPAMURAI).value!
  end

  # Enable using Spamurai for Bayes checks.
  def self.enable_spamurai(user = nil)
    Spam::Kv.store.set(USE_SPAMURAI, "enabled")
    message = "Spamurai *enabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  # Disable using Spamurai for Bayes checks.
  def self.disable_spamurai(user = nil)
    Spam::Kv.store.set(USE_SPAMURAI, "disabled")
    message = "Spamurai *disabled*"
    message += " by #{user}" if user
    notify(channel: "platform-health-ops", message: message)
  end

  # If there's not a threshold set, return a default of 99%,
  # which will pretty much turn it off.
  def self.get_bayes_gist_confidence_threshold
    (Spam::Kv.store.get(BAYES_GIST_CONFIDENCE_THRESHOLD).value! || 0.99).to_f
  end

  # Put a lower-bound sanity check on setting the confidence threshold;
  # especially don't set it to 0.
  def self.set_bayes_gist_confidence_threshold(value)
    real_value = value.to_f
    if real_value > 1.0
      real_value /= 100.0
    end
    return unless real_value >= 0.001
    old_value = get_bayes_gist_confidence_threshold
    Spam::Kv.store.set(BAYES_GIST_CONFIDENCE_THRESHOLD, real_value.to_s)
    notify(channel: "platform-health-ops", bayes_gist_confidence_threshold: "message changed from #{old_value} to #{real_value}")
  end

  # If there's not a threshold set, return a default of 99%,
  # which will pretty much turn it off.
  def self.get_bayes_comment_confidence_threshold
    (Spam::Kv.store.get(BAYES_COMMENT_CONFIDENCE_THRESHOLD).value! || 0.99).to_f
  end

  # Put a lower-bound sanity check on setting the confidence threshold;
  # especially don't set it to 0.
  def self.set_bayes_comment_confidence_threshold(value)
    real_value = value.to_f
    if real_value > 1.0
      real_value /= 100.0
    end
    return unless real_value >= 0.001
    old_value = get_bayes_comment_confidence_threshold
    Spam::Kv.store.set(BAYES_COMMENT_CONFIDENCE_THRESHOLD, real_value.to_f)
    notify(channel: "platform-health-ops", message: "bayes_comment_confidence_threshold changed from #{old_value} to #{real_value}")
  end

  NOTIFICATION_EVENT_NAME = "spam.notification"
  DEFAULT_NOTIFICATION_CHANNEL = "spam-notifications"

  def self.notify(actor: nil, channel: DEFAULT_NOTIFICATION_CHANNEL, message:)
    GlobalInstrumenter.instrument NOTIFICATION_EVENT_NAME, {
      actor: actor,
      channel: channel,
      message: message,
    }
  end
end
