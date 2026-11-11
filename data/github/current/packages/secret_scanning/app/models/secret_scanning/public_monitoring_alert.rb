# typed: strict
# frozen_string_literal: true

module SecretScanning
  # Typed model for a single public monitoring alert.
  class PublicMonitoringAlert < T::Struct
    const :business_id, Integer
    const :id, Integer
    const :repository_id, Integer
    const :secret_author_id, Integer
    const :slug, String
    const :label, String
    const :token_type_provider, String
    const :alert_number, Integer
    const :created_at, T.nilable(Time)
    const :validity, String
    const :resolution, String
    const :encrypted_token, T.nilable(String)
    const :is_base64_encoded, T::Boolean, default: false
    prop :raw_secret, T.nilable(String)
    prop :decoded_base64_raw_secret, T.nilable(String), default: nil
    const :attribution_heuristic, String

    # Proto enum reference for attribution method values
    AttributionMethod = GitHub::Proto::SecretScanning::PublicMonitoring::V1::AttributionMethod
    ATTRIBUTION_METHOD_UNSPECIFIED = T.let(T.must(AttributionMethod.lookup(AttributionMethod::ATTRIBUTION_METHOD_UNSPECIFIED)), Symbol)
    ATTRIBUTION_METHOD_MEMBERSHIP = T.let(T.must(AttributionMethod.lookup(AttributionMethod::ATTRIBUTION_METHOD_MEMBERSHIP)), Symbol)

    # Maps internal proto enum names to user-facing display values for API, webhook, and UI surfaces.
    DISPLAY_ATTRIBUTION_METHODS = T.let({
      "ATTRIBUTION_METHOD_MEMBERSHIP" => "member_activity",
      "ATTRIBUTION_METHOD_VERIFIED_DOMAIN" => "verified_domain",
    }.freeze, T::Hash[String, String])

    sig { params(raw: String).returns(String) }
    def self.display_attribution_method(raw)
      DISPLAY_ATTRIBUTION_METHODS[raw] || raw
    end

    const :attribution_method, String, default: ATTRIBUTION_METHOD_MEMBERSHIP.to_s
    const :repository_name, String
    const :committer_identifier, String
    const :committer_email, T.nilable(String)
    const :committer_avatar_url, T.nilable(String)
    const :repository, T.nilable(Repository)
    const :secret_author, T.nilable(User)
    const :first_location, T.nilable(GitHub::TokenScanning::Service::TokenLocation)

    sig do
      params(
        proto: GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert,
        business_id: Integer,
        repository: T.nilable(Repository),
        repository_name: String,
        committer_identifier: String,
        committer_email: T.nilable(String),
        committer_avatar_url: T.nilable(String),
        secret_author: T.nilable(User),
        first_location: T.nilable(GitHub::TokenScanning::Service::TokenLocation),
      ).returns(PublicMonitoringAlert)
    end
    def self.from_proto(proto, business_id:, repository:, repository_name:, committer_identifier:, committer_email:, committer_avatar_url:, secret_author: nil, first_location: nil)
      # Default to MEMBERSHIP when TSS hasn't populated attribution_method yet.
      # attribution_heuristic is deprecated and will be removed.
      attribution_method = if proto.attribution_method != ATTRIBUTION_METHOD_UNSPECIFIED
        proto.attribution_method.to_s
      else
        ATTRIBUTION_METHOD_MEMBERSHIP.to_s
      end

      created_at = proto.created_at&.to_time
      attribution_heuristic = proto.attribution_heuristic.to_s

      new(
        business_id: business_id,
        id: proto.id,
        repository_id: proto.repository_id,
        secret_author_id: proto.secret_author_id,
        slug: proto.slug,
        label: proto.label,
        token_type_provider: proto.token_type_provider,
        alert_number: proto.alert_number,
        created_at: created_at,
        validity: proto.validity.to_s,
        resolution: proto.resolution.to_s,
        encrypted_token: proto.encrypted_token,
        attribution_heuristic: attribution_heuristic,
        attribution_method: attribution_method,
        repository: repository,
        repository_name: repository_name,
        committer_identifier: committer_identifier,
        committer_email: committer_email,
        committer_avatar_url: committer_avatar_url,
        secret_author: secret_author,
        first_location: first_location,
        # Note: is_base64_encoded defaults to false; not provided by the proto.
      )
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def serialize_ui
      {
        alertKey: SecretScanning::Encryption::PublicMonitoringAlertKey.encrypt(repository_id, alert_number, business_id),
        # TODO: remove repositoryId and alertNumber once the github-ui PR ships
        repositoryId: repository_id,
        alertNumber: alert_number,
        secretAuthorId: secret_author_id,
        slug: slug,
        label: label,
        secretTypeLabel: label,
        tokenTypeProvider: token_type_provider,
        createdAt: created_at,
        validity: validity,
        resolution: resolution,
        rawSecret: raw_secret,
        attributionHeuristic: attribution_heuristic,
        attributionMethod: self.class.display_attribution_method(attribution_method),
        repositoryName: repository_name,
        committerIdentifier: committer_identifier,
        committerEmail: committer_email,
        committerAvatarUrl: committer_avatar_url,
      }
    end
  end
end
