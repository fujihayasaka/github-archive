# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  class LowerConfidencePatterns
    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @lower_confidence_patterns = if @owner.is_a?(Business)
        SecretScanning::Features::Business::LowerConfidencePatterns.new(@owner)
      elsif @owner.is_a?(Organization)
        SecretScanning::Features::Org::LowerConfidencePatterns.new(@owner)
      elsif @owner.is_a?(User)
        SecretScanning::Features::User::LowerConfidencePatterns.new(@owner)
      end
    end

    sig { returns(T::Boolean) }
    def enabled_by_owning_business?
      return false unless @owner.is_a?(Organization)
      @lower_confidence_patterns.enabled_by_enterprise?
    end

    delegate :feature_available?,
             :enabled?,
             :enable,
             :disable,
             :show_security_config_ux?,
             :enabled_for_new_repos?,
      to: :@lower_confidence_patterns
  end
end
