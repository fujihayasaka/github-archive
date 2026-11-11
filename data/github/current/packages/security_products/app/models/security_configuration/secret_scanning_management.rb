# typed: strict
# frozen_string_literal: true

# Encapsulates secret scanning configuration management:
# delegated bypass reviewer lifecycle and state-change predicates.
module SecurityConfiguration::SecretScanningManagement
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  # -- State-change predicates ------------------------------------------------

  sig { returns(T::Boolean) }
  def secret_scanning_scan_triggering_feature_is_enabled?
    secret_scanning_is_enabled? || secret_scanning_generic_secrets_is_enabled? || secret_scanning_non_provider_patterns_is_enabled?
  end

  sig { returns(T::Boolean) }
  def secret_scanning_is_enabled?
    secret_scanning_enabled? && (secret_scanning_previously_was == "disabled" || secret_scanning_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_generic_secrets_is_enabled?
    secret_scanning_generic_secrets_enabled? && (secret_scanning_generic_secrets_previously_was == "disabled" || secret_scanning_generic_secrets_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_non_provider_patterns_is_enabled?
    secret_scanning_non_provider_patterns_enabled? && (secret_scanning_non_provider_patterns_previously_was == "disabled" || secret_scanning_non_provider_patterns_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_delegated_bypass_is_disabled_or_not_set?
    (secret_scanning_delegated_bypass_disabled? || secret_scanning_delegated_bypass_not_set?) && secret_scanning_delegated_bypass_previously_was == "enabled"
  end

  # -- Delegated bypass reviewer lifecycle ------------------------------------

  sig { params(actor: User, options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), ActionController::Parameters)).void }
  def update_secret_scanning_delegated_bypass(actor, options)
    if secret_scanning_delegated_bypass_is_disabled_or_not_set?
      SecretScanning::Services::DelegatedBypassService.remove_bypassers_for_source(
        target,
        id,
        actor,
      )
    elsif secret_scanning_delegated_bypass_enabled? &&
        !options.nil? &&
        options[:secret_scanning_delegated_bypass].present? &&
        options[:secret_scanning_delegated_bypass][:reviewers].present?
      update_secret_scanning_bypass_reviewers(options, actor)
    end
  end

  sig { params(options: T.any((T::Hash[Symbol, T.untyped]), ActionController::Parameters), actor: User).void }
  def update_secret_scanning_bypass_reviewers(options, actor)
    bypassers = T.let([], T::Array[GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser])
    reviewers = T.let(options[:secret_scanning_delegated_bypass][:reviewers], T::Array[T::Hash[String, T.untyped]])
    reviewers.each do |reviewer|
      bypassers << GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser.new(
        owner_id: target_id,
        owner_scope: SecretScanning::Services::DelegatedBypassService.get_owner_scope_for_configuration(T.cast(self, SecurityConfiguration)),
        security_configuration_id: id,
        bypasser_id: reviewer["actorId"],
        bypasser_type: SecretScanning::Services::DelegatedBypassService.get_bypasser_type_from_actor_type(reviewer["actorType"]),
        mode: reviewer["bypassMode"] || :ALWAYS,
      )
    end

    SecretScanning::Services::DelegatedBypassService.update_bypassers_for_source(
      target,
      id,
      bypassers,
      actor
    )
  end
end
