# typed: strict
# frozen_string_literal: true

module Copilot
  class GetDependabotAlertSkillResponse
    include GitHub::Memoizer

    sig { returns(Repository) }
    attr_reader :current_repository

    sig { returns(RepositoryVulnerabilityAlert) }
    attr_reader :alert

    sig { params(alert: RepositoryVulnerabilityAlert, current_repository: ::Repository).void }
    def initialize(alert:, current_repository:)
      @alert = alert
      @current_repository = current_repository
    end

    sig { returns(MonolithTwirp::Copilotapi::Chat::V1::GetDependabotAlertResponse) }
    def payload
      MonolithTwirp::Copilotapi::Chat::V1::GetDependabotAlertResponse.new(
        alert: MonolithTwirp::Copilotapi::Chat::V1::DependabotAlert.new(
          active: alert.active,
          affected_package_name: alert.vulnerable_version_range.try(:affects),
          affected_range: alert.vulnerable_version_range.try(:requirements),
          created_at: proto_timestamp(alert.created_at),
          cve_id: alert.vulnerability.try(:cve_id),
          description: alert.vulnerability.try(:description),
          external_identifier: alert.vulnerability.try(:identifier),
          external_reference: alert.vulnerability.try(:permalink),
          ghsa_id: alert.vulnerability.try(:ghsa_id),
          help_urls:,
          last_state_change_at: proto_timestamp(alert.last_state_change_at),
          last_state_change_pull_request_id: alert.last_state_change_pull_request_id,
          last_state_change_push_id: alert.last_state_change_push_id,
          last_state_change_reason: alert.last_state_change_reason,
          number: alert.number,
          nvd_published_at: proto_timestamp(alert.vulnerability.try(:nvd_published_at)),
          published_at: proto_timestamp(alert.vulnerability.try(:published_at)),
          related_files:,
          repo_id: alert.repository_id,
          security_advisory_id: alert.vulnerability.try(:security_advisory_id),
          severity: alert.vulnerability.try(:severity).try(:to_s).try(:downcase),
          state: alert.state,
          summary: alert.vulnerability.try(:summary),
          title: alert.title,
          updated_at: proto_timestamp(alert.updated_at),
          url: UrlHelpers.repository_alert_path(current_repository.owner, current_repository, number: alert.number),
          vulnerable_manifest_path: alert.vulnerable_manifest_path,
          withdrawn_at: proto_timestamp(alert.vulnerability.try(:withdrawn_at))
        )
      )
    end

    private

    sig { returns(T::Array[String]) }
    def help_urls
      return [] if alert.vulnerability.try(:vulnerability_references).blank?

      T.must(alert.vulnerability)
        .vulnerability_references
        .map { |vuln_ref| vuln_ref.url }
        .compact
    end

    sig { params(timestamp: T.nilable(ActiveSupport::TimeWithZone)).returns(T.nilable(Google::Protobuf::Timestamp)) }
    def proto_timestamp(timestamp)
      return nil unless timestamp
      Google::Protobuf::Timestamp.new(seconds: timestamp.to_i, nanos: timestamp.nsec)
    end

    sig { returns(T::Array[MonolithTwirp::Copilotapi::Chat::V1::AlertFile]) }
    def related_files
      file_paths = []
      blob_paths_with_commit = []

      return [] if blob_paths_with_commit.empty?

      blob_oids = current_repository.rpc.read_blob_oids(blob_paths_with_commit, skip_bad: true)

      file_path_by_oid = Hash[blob_oids.zip(file_paths)]

      found_blobs = blob_oids.select(&:present?)

      return [] if found_blobs.empty?

      current_repository.read_objects(
        found_blobs, :blob).filter_map do |raw_blob|
        next if raw_blob["binary"]
        path = file_path_by_oid[raw_blob["oid"]]
        next unless path
        MonolithTwirp::Copilotapi::Chat::V1::AlertFile.new(
          path: path.dup.force_encoding("UTF-8").scrub!,
          contents: raw_blob["data"].dup.force_encoding("UTF-8").scrub!,
        )
      end
    end
  end
end
