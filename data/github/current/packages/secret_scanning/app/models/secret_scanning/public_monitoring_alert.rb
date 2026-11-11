# typed: strict
# frozen_string_literal: true

module SecretScanning
  # Typed model for a single public monitoring alert.
  class PublicMonitoringAlert < T::Struct
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
    const :repository_name, String
    const :committer_identifier, String
    const :committer_email, T.nilable(String)
    const :committer_avatar_url, T.nilable(String)

    sig do
      params(
        proto: GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert,
        repository_name: String,
        committer_identifier: String,
        committer_email: T.nilable(String),
        committer_avatar_url: T.nilable(String),
      ).returns(PublicMonitoringAlert)
    end
    def self.from_proto(proto, repository_name:, committer_identifier:, committer_email:, committer_avatar_url:)
      new(
        repository_id: proto.repository_id,
        secret_author_id: proto.secret_author_id,
        slug: proto.slug,
        label: proto.label,
        token_type_provider: proto.token_type_provider,
        alert_number: proto.alert_number,
        created_at: proto.created_at&.to_time,
        validity: proto.validity.to_s,
        resolution: proto.resolution.to_s,
        encrypted_token: proto.encrypted_token,
        attribution_heuristic: proto.attribution_heuristic.to_s,
        repository_name: repository_name,
        committer_identifier: committer_identifier,
        committer_email: committer_email,
        committer_avatar_url: committer_avatar_url,
      )
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def serialize_ui
      {
        alertKey: SecretScanning::Encryption::PublicMonitoringAlertKey.encrypt(repository_id, alert_number),
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
        repositoryName: repository_name,
        committerIdentifier: committer_identifier,
        committerEmail: committer_email,
        committerAvatarUrl: committer_avatar_url,
      }
    end
  end
end
