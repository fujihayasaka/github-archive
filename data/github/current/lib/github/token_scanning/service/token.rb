# typed: true
# frozen_string_literal: true

# Wrapper class for the protobuf token class returned from the service.
#
# Implements the same methods as `TokenScanResult` so that is can be used
# interchangeably in the views.
class GitHub::TokenScanning::Service::Token
  include GitHub::Memoizer
  include SecretScanning::Features::FeatureFlagHelper

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Token) }
  attr_reader :token

  attr_reader :first_location, :included_locations_count, :included_locations, :has_ignored_locations, :commit_oids, :repository,
    :custom_pattern, :related_alerts, :related_public_leaks

  # Transient fields that are used to compute and return fields for API responses
  attr_accessor :raw_secret, :slug_type, :decoded_base64_raw_secret

  delegate :id, :repository_id, :token_type, :number, :resolver_id, :scan_scope, :label, :token_type_provider, :external_remediation_doc_url, :encrypted_token, :low_confidence, :llm_detected, :multi_repo, :publicly_leaked, to: :token

  # TODO add type to `data` param
  sig { params(token: GitHub::Proto::SecretScanning::Api::V2::Token, repository: Repository, data: T.untyped).void }
  def initialize(token, repository, data = nil)
    @token = token
    @repository = repository

    if token.first_location.present?
      @first_location = GitHub::TokenScanning::Service::TokenLocation.new(token.first_location, repository)
    end

    @commit_oids = data&.commit_oids || [first_location&.commit_oid].compact
    @custom_pattern = data.custom_pattern_data if data.present?
    @has_ignored_locations = data&.has_ignored_locations || false
    @included_locations_count = data&.included_locations_count || 0
    @included_locations = data&.included_locations || []
    @included_locations = @included_locations.map do |location|
      GitHub::TokenScanning::Service::TokenLocation.new(location, repository)
    end
    @related_alerts = data&.related_alerts || []
    @related_alerts = @related_alerts.map do |alert|
      GitHub::TokenScanning::Service::RelatedToken.new(
        repository_id: alert.repository_id,
        number: alert.number,
        token_type: alert.token_type
      )
    end
    @related_public_leaks = data&.related_public_leaks || []
    @related_public_leaks = @related_public_leaks.map do |public_leak|
      GitHub::TokenScanning::Service::RelatedPublicLeak.new(
        repository_id: public_leak.repository_id,
        location: public_leak.location
      )
    end
  end

  def created_at
    token.created_at&.to_time
  end

  def resolved_at
    token.resolved_at&.to_time
  end

  def last_modified_at
    token.updated_at&.to_time
  end

  def resolution
    return @resolution if defined? @resolution

    @resolution = if token.resolution != :NO_RESOLUTION
      token.resolution.to_s.downcase
    else
      nil
    end
  end

  def resolver
    return @resolver if defined? @resolver

    @resolver = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: token.resolver_id) }
  end

  def resolved?
    resolution.present? && !reopened?
  end

  def reopened?
    resolution == "reopened"
  end

  def revoked?
    resolution == "revoked"
  end

  def found_in_archive?
    first_location.present? && first_location.found_in_archive?
  end

  def is_custom?
    token.token_type.start_with?("cp_")
  end

  def raw_secret_in_git_history?
    raw_secret && raw_secret != SecretScanning::Util::RawSecret::BLOB_NOT_FOUND
  end

  sig { returns(T::Boolean) }
  def validity_active?
    token.validity == :TOKEN_VALIDITY_ACTIVE
  end

  sig { returns(T::Boolean) }
  def is_github_token?
    github_types = %w(GITHUB GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_OAUTH_ACCESS_TOKEN GITHUB_USER_TO_SERVER_TOKEN GITHUB_REFRESH_TOKEN GITHUB_SERVER_TO_SERVER_TOKEN GITHUB_APP_TOKEN ARMORED_PEM_PRIVATE_KEY GITHUB_SSH_PRIVATE_KEY GITHUB_TOKEN_V2).freeze
    github_types.include?(token.token_type)
  end

  sig { returns(T::Boolean) }
  def is_classic_or_fine_grained_pat?
    github_types = %w(GITHUB GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_TOKEN_V2).freeze
    github_types.include?(token.token_type)
  end

  sig { returns(T::Boolean) }
  def first_location_in_actions_file?
    return false if @first_location.nil?
    loc = T.cast(@first_location, GitHub::TokenScanning::Service::TokenLocation)
    return false if loc.path.nil?
    loc.path.include?(".github/workflows")
  end

  sig { returns(T::Boolean) }
  def is_aws_token?
    aws_types = "%w(AWS_KEYID AWS_SECRET AWS_SESSION_TOKEN AWS_TEMPORARY_ACCESS_KEY_ID)"
    aws_types.include?(token.token_type)
  end

  sig { returns(T::Boolean) }
  def is_async_validated_token?
    async_types = %w(MICROSOFT_AZURE_APP_CONFIGURATION_CONNECTION_STRING MICROSOFT_AZURE_COMMUNICATION_SERVICES_CONNECTION_STRING MICROSOFT_AZURE_IOT_DEVICE_CONNECTION_STRING MICROSOFT_AZURE_IOT_HUB_CONNECTION_STRING MICROSOFT_AZURE_IOT_PROVISIONING_CONNECTION_STRING NUGET_API_KEY).freeze
    async_types.include?(token.token_type)
  end

  sig { returns(T.nilable(Time)) }
  def validity_last_checked
    token.validation_details&.validity_last_checked&.to_time
  end

  sig { returns(T.nilable(Time)) }
  def async_check_requested_at
    token.validation_details&.async_check_requested_at&.to_time
  end

  sig { returns(Symbol) }
  def validity
    T.unsafe(token.validity)
  end

  sig { returns(T::Boolean) }
  def on_demand_checks_supported?
    # For GitHub tokens, on-demand checks are always supported (regardless of environment) if TSS allows them.
    if is_github_token?
      return token.validation_support&.on_demand_checks_supported || false
    end
    # In enterprise, on-demand checks are not supported for partner (non-GitHub) token types
    return false if GitHub.single_or_multi_tenant_enterprise?
    # On cloud, on-demand checks are supported for partner token types if TSS allows them.
    token.validation_support&.on_demand_checks_supported || false
  end

  sig { returns(T::Boolean) }
  def on_demand_check_allowed?
    return false unless on_demand_checks_supported?
    return false if is_multipart && token_groups.length == 0
    return false if async_check_in_progress?
    return true if validity_last_checked.nil?
    diff = (Time.now.utc - (T.must(validity_last_checked)).utc) / 1.minute
    diff >= 1.0
  end

  sig { returns(T::Boolean) }
  def async_check_in_progress?
    self.class.async_check_in_progress?(async_check_requested_at)
  end

  sig { params(async_check_requested_at: T.nilable(Time)).returns(T::Boolean) }
  def self.async_check_in_progress?(async_check_requested_at)
    return false if async_check_requested_at.nil?
    diff = (Time.now.utc - (T.must(async_check_requested_at)).utc) / 1.minute
    diff <= 5.0
  end

  sig { returns(T::Boolean) }
  def is_multipart
    token.is_multipart
  end

  sig { returns(T::Boolean) }
  def is_reported
    token.is_reported
  end

  sig { returns(T::Boolean) }
  def is_base64_encoded
    token.is_base64_encoded
  end

  sig { returns(T::Boolean) }
  def validity_checks_supported?
    # For GitHub tokens, validity checks are always supported (regardless of environment) if TSS allows them.
    if is_github_token?
      return token.validation_support&.validity_checks_supported || false
    end
    # In enterprise, validity checks are not supported for partner (non-GitHub) token types
    return false if GitHub.single_or_multi_tenant_enterprise?
    # On cloud, validity checks are supported for partner token types if TSS allows them.
    token.validation_support&.validity_checks_supported || false
  end

  sig { returns(T.nilable(Integer)) }
  def bypasser_id
    token.push_protection_bypassed_by_user_id
  end

  sig { returns(T.nilable(User)) }
  def bypasser
    return @bypasser if defined? @bypasser

    @bypasser = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: token.push_protection_bypassed_by_user_id) }
  end

  sig { params(user: T.nilable(User)).void }
  def set_bypasser(user)
    @bypasser = user
  end

  sig { params(user: T.nilable(User)).void }
  def set_resolver(user)
    @resolver = user
  end

  sig { returns(T::Array[SecretScanning::Models::Validity::TokenGroup]) }
  memoize def token_groups
    token.token_groups.to_a.map { |token_group| SecretScanning::Models::Validity::TokenGroup.from_proto(token_group) }
  end
end
