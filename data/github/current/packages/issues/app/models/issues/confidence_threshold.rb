# typed: strict
# frozen_string_literal: true

module Issues
  # Thin wrapper around Issues::KV for storing per-repo confidence thresholds
  # that determine whether agentic mutations are auto-applied or routed as suggestions.
  #
  # Keys follow the pattern: issues/confidence_threshold/repo:<repo_id>
  # Values are enum level strings stored in KV.
  # Each level maps to a numeric score used for comparison:
  #   LOW = 25, MEDIUM = 50, HIGH = 75
  #
  # Lookup logic: per-repo threshold → nil (pass-through / no threshold).
  #
  # ## Feature-flag spike mode (temporary)
  #
  # When the parent flag `issues_confidence_threshold_use_feature_flags` is enabled for a
  # repository, threshold lookup bypasses the KV store entirely and instead checks three
  # per-level feature flags:
  #   - `issues_confidence_threshold_low`
  #   - `issues_confidence_threshold_medium`
  #   - `issues_confidence_threshold_high`
  #
  # The highest enabled flag wins (HIGH > MEDIUM > LOW). If none are enabled, no threshold
  # is applied (pass-through).
  #
  # This is a **spike-only mechanism** to allow rapid iteration without needing to update
  # KV store values directly. The three level flags are ONLY checked when the parent flag
  # is enabled — this avoids unnecessary feature flag evaluations in the normal path.
  # Once we settle on a long-term approach (easy KV management or permanent flag-based
  # config), this spike path should be removed.
  class ConfidenceThreshold
    KEY_PREFIX = T.let("issues/confidence_threshold/repo", String)

    class Level < T::Enum
      enums do
        LOW = new("LOW")
        MEDIUM = new("MEDIUM")
        HIGH = new("HIGH")
      end

      sig { returns(Integer) }
      def score
        case self
        when LOW then 25
        when MEDIUM then 50
        when HIGH then 75
        else T.absurd(self)
        end
      end

      # Case-insensitive variant of try_deserialize that also tolerates non-String input
      # (returns nil instead of raising).
      sig { params(value: T.untyped).returns(T.nilable(Level)) }
      def self.try_parse(value)
        return nil unless value.is_a?(String)
        try_deserialize(value.upcase)
      end

      # Reverse mapping from numeric score to Level enum.
      # Returns nil for unrecognized scores.
      sig { params(score: T.nilable(Integer)).returns(T.nilable(Level)) }
      def self.from_score(score)
        values.find { |level| level.score == score }
      end
    end

    class InvalidThresholdError < StandardError; end

    # Retrieve the numeric confidence score for a repository.
    # Returns the integer score (25, 50, or 75) or nil if not set.
    sig { params(repository: Repository).returns(T.nilable(Integer)) }
    def self.get_threshold(repository)
      level = get_threshold_level(repository)
      level&.score
    end

    # Retrieve the stored enum level for a repository, or nil if not set.
    # Routes to feature-flag-based lookup when the parent flag is enabled.
    sig { params(repository: Repository).returns(T.nilable(Level)) }
    def self.get_threshold_level(repository)
      if use_feature_flags?(repository)
        get_threshold_level_from_flags(repository)
      else
        get_threshold_level_from_kv(repository.id)
      end
    end

    # Set the confidence threshold for a repository using an enum level.
    sig { params(repository_id: Integer, level: Level).void }
    def self.set_threshold(repository_id, level)
      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(key(repository_id), level.serialize)
    end

    # Delete the confidence threshold for a repository.
    # After deletion, get_threshold will return nil (pass-through).
    sig { params(repository_id: Integer).void }
    def self.delete_threshold(repository_id)
      kv = Issues::KV.for_repository_id(repository_id)
      kv.del(key(repository_id))
    end

    # Determine whether a confidence level should be routed as a suggestion.
    # Returns true if the confidence is below the stored threshold, false otherwise.
    # Returns false if confidence is nil or no threshold is configured (pass-through).
    sig { params(repository: Repository, confidence: T.nilable(Level)).returns(T::Boolean) }
    def self.should_suggest?(repository:, confidence:)
      return false if confidence.nil?

      threshold = get_threshold(repository)
      return false unless threshold

      confidence.score < threshold
    end

    # Check whether the spike feature-flag path is active for this repository.
    sig { params(repository: Repository).returns(T::Boolean) }
    def self.use_feature_flags?(repository)
      FeatureFlag.vexi.enabled?(:issues_confidence_threshold_use_feature_flags, repository, default: false)
    end
    private_class_method :use_feature_flags?

    # Determine threshold level from feature flags. Highest enabled flag wins.
    # Only called when the parent flag is enabled.
    sig { params(repository: Repository).returns(T.nilable(Level)) }
    def self.get_threshold_level_from_flags(repository)
      if FeatureFlag.vexi.enabled?(:issues_confidence_threshold_high, repository, default: false)
        Level::HIGH
      elsif FeatureFlag.vexi.enabled?(:issues_confidence_threshold_medium, repository, default: false)
        Level::MEDIUM
      elsif FeatureFlag.vexi.enabled?(:issues_confidence_threshold_low, repository, default: false)
        Level::LOW
      end
    end
    private_class_method :get_threshold_level_from_flags

    # Retrieve threshold level from the KV store (original behavior).
    sig { params(repository_id: Integer).returns(T.nilable(Level)) }
    def self.get_threshold_level_from_kv(repository_id)
      kv = Issues::KV.for_repository_id(repository_id)
      value = kv.get(key(repository_id)).value!
      return nil unless value

      Level.try_deserialize(value)
    end
    private_class_method :get_threshold_level_from_kv

    sig { params(repository_id: Integer).returns(String) }
    def self.key(repository_id)
      "#{KEY_PREFIX}:#{repository_id}"
    end
    private_class_method :key
  end
end
