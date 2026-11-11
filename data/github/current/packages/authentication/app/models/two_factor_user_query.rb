# typed: strict
# frozen_string_literal: true

# Query helpers that return user IDs based on two-factor authentication state.
#
# These helpers query auth-owned tables (two_factor_credentials, two_factor_requirement_metadata,
# sms_registrations) directly and return user IDs. This avoids cross-cluster joins when these
# tables move to the auth-owned database cluster.
#
# Each method accepts optional `user_ids:` to scope the query. When provided,
# queries are batched via `batched_scope` (10K per batch). When nil, queries run globally.
#
# Callers hydrate User objects separately via User.where(id: ...).
#
# Examples:
#   # Scoped — enabled users among org members
#   enabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_enabled(user_ids: org.member_ids)
#
#   # Disabled — users WITHOUT 2FA among candidates
#   disabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_disabled(user_ids: org.member_ids)
#
#   # Existence check with early exit
#   TwoFactorUserQuery.users_with_two_factor_disabled_exist?(user_ids: org.member_ids)
#
#   # Count without materializing all IDs
#   TwoFactorUserQuery.users_with_two_factor_enabled_count(user_ids: org.member_ids)
#   TwoFactorUserQuery.users_with_two_factor_disabled_count(user_ids: org.member_ids)
#
module TwoFactorUserQuery
  BATCH_SIZE = 10_000

  # -- Enabled (has two_factor_credential) --

  # Returns user IDs that have a two_factor_credential.
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Array[Integer]) }
  def self.user_ids_with_two_factor_enabled(user_ids:)
    TwoFactorCredential.batched_scope(:user_id, values: Array(user_ids).uniq, batch_size: BATCH_SIZE)
        .pluck(:user_id)
  end

  # Returns count of two-factor enabled users among candidates.
  sig { params(user_ids: T::Enumerable[Integer]).returns(Integer) }
  def self.users_with_two_factor_enabled_count(user_ids:)
    TwoFactorCredential.batched_scope(:user_id, values: Array(user_ids).uniq, batch_size: BATCH_SIZE).count
  end

  # -- Disabled (no two_factor_credential) --

  # Returns user IDs from candidates that do NOT have a two_factor_credential.
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Array[Integer]) }
  def self.user_ids_with_two_factor_disabled(user_ids:)
    unique_ids = Array(user_ids).uniq
    result = T.let([], T::Array[Integer])

    unique_ids.each_slice(BATCH_SIZE) do |batch|
      enabled_ids = TwoFactorCredential.where(user_id: batch).pluck(:user_id)
      enabled_set = Set.new(enabled_ids)
      result.concat(batch.reject { |id| enabled_set.include?(id) })
    end

    result
  end

  # Returns true if any candidate user lacks a two_factor_credential. Early-exits per batch.
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Boolean) }
  def self.users_with_two_factor_disabled_exist?(user_ids:)
    unique_ids = Array(user_ids).uniq
    unique_ids.each_slice(BATCH_SIZE) do |batch|
      enabled_count = TwoFactorCredential.where(user_id: batch).count
      return true if enabled_count < batch.size
    end
    false
  end

  # Returns count of two-factor disabled users among candidates.
  sig { params(user_ids: T::Enumerable[Integer]).returns(Integer) }
  def self.users_with_two_factor_disabled_count(user_ids:)
    unique_ids = Array(user_ids).uniq
    unique_ids.size - users_with_two_factor_enabled_count(user_ids: unique_ids)
  end

  # -- Required (has requirement metadata in required/warning/interrupt state) --

  # Returns user IDs in required/warning/interrupt 2FA requirement states.
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Array[Integer]) }
  def self.user_ids_with_two_factor_required(user_ids:)
    required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES
    .slice(:required, :warning, :interrupt).values

    TwoFactorRequirementMetadata.batched_scope(
      :user_id, values: Array(user_ids).uniq, batch_size: BATCH_SIZE
    ) { |scope| scope.where(state: required_states) }.pluck(:user_id)
  end

  # Returns requirement metadata keyed by user_id for users in required/warning/interrupt states.
  # Useful when callers need metadata fields (e.g., required_by date) beyond just IDs.
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Hash[Integer, TwoFactorRequirementMetadata]) }
  def self.two_factor_requirement_metadata_by_user_id(user_ids:)
    required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES
      .slice(:required, :warning, :interrupt).values

    result = T.let({}, T::Hash[Integer, TwoFactorRequirementMetadata])

    Array(user_ids).uniq.each_slice(BATCH_SIZE) do |batch|
      TwoFactorRequirementMetadata
        .where(user_id: batch, state: required_states)
        .each { |metadata| result[metadata.user_id] = metadata }
    end

    result
  end

  # -- Insecure methods (has sms_registration) --

  # Returns user IDs that have sms_registrations (insecure 2FA methods).
  sig { params(user_ids: T::Enumerable[Integer]).returns(T::Array[Integer]) }
  def self.user_ids_with_insecure_two_factor_method(user_ids:)
    unless Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS.include?(:sms)
      return [] # :nocov:
    end

    SmsRegistration.batched_scope(
      :user_id, values: Array(user_ids).uniq, batch_size: BATCH_SIZE
    ) { |scope| scope.distinct }.pluck(:user_id)
  end
end
