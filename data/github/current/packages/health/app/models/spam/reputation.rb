# typed: true
# frozen_string_literal: true

module Spam
  class Reputation
    WARNING_THRESHOLD = 0.5
    CRITICAL_THRESHOLD = 0.8

    # Public: Default reputation to use when you know you can't generate a reputation.
    #
    # Returns instance of Spam::Reputation.
    def self.default
      new({
        sample_size: 0,
        not_spammy_sample_size: 0,
        spammy_sample_size: 0,
        reputation: 1.0,
        reputation_lower_bound: 1.0,
        plus_minus: 0.0,
        maximum_reputation: 1.0,
        minimum_reputation: 1.0,
        warning_level: :low
      })
    end

    # Public: Generate a reputation for given sample_size and not_spammy_sample_size.
    #
    # sample_size: Integer.
    # not_spammy_sample_size: Integer.
    #
    # Returns instance of Spam::Reputation.
    def self.generate(sample_size:, not_spammy_sample_size:)
      return default unless sample_size > 0
      return default unless not_spammy_sample_size >= 0
      return default unless sample_size >= not_spammy_sample_size

      # Models reputation as the estimated proportion of good items to all items,
      # with a 95% confidence interval, using the normal approximation interval.
      # It returns two values: the estimated reputation and the interval
      # at 95% confidence. See http://bit.ly/2yD5TvJ for more details.

      p_hat = not_spammy_sample_size.to_f / sample_size # p̂ -- estimated proportion
      z_score = 1.95996 # z-score for 95% confidence
      z_squared = z_score**2
      plus_minus = z_score * Math.sqrt((p_hat * (1.0 - p_hat)) / sample_size)
      lower_bound = ((2 * sample_size * p_hat) + z_squared - (z_score * Math.sqrt(z_squared + (4 * sample_size * p_hat * (1.0 - p_hat))))) / (2 * (sample_size + z_squared))

      maximum_reputation = (p_hat + plus_minus) > 1 ? 1.0 : (p_hat + plus_minus)
      minimum_reputation = (p_hat - plus_minus) < 0 ? 0.0 : (p_hat - plus_minus)

      warning_level = :low
      spammyness = 1 - p_hat

      if spammyness >= CRITICAL_THRESHOLD
        warning_level = :critical
      elsif spammyness >= WARNING_THRESHOLD
        warning_level = :warning
      end

      new({
        sample_size: sample_size,
        not_spammy_sample_size: not_spammy_sample_size,
        spammy_sample_size: sample_size - not_spammy_sample_size,
        reputation: p_hat,
        reputation_lower_bound: lower_bound.round(4),
        plus_minus: plus_minus,
        maximum_reputation: maximum_reputation,
        minimum_reputation: minimum_reputation,
        warning_level: warning_level,
      })
    end

    def initialize(attrs)
      @sample_size = attrs[:sample_size]
      @not_spammy_sample_size = attrs[:not_spammy_sample_size]
      @spammy_sample_size = attrs[:spammy_sample_size]
      @reputation = attrs[:reputation]
      @reputation_lower_bound = attrs[:reputation_lower_bound]
      @plus_minus = attrs[:plus_minus]
      @maximum_reputation = attrs[:maximum_reputation]
      @minimum_reputation = attrs[:minimum_reputation]
      @warning_level = attrs[:warning_level]
    end

    attr_reader :sample_size, :not_spammy_sample_size, :spammy_sample_size, :reputation,
      :reputation_lower_bound, :plus_minus, :maximum_reputation, :minimum_reputation, :warning_level

    def platform_type_name
      "SpamuraiReputation"
    end
  end
end
