# typed: strict
# frozen_string_literal: true

module Copilot
  class GetSecretScanningAlertSkillResponse
    include GitHub::Memoizer

    OTHER_LOCATIONS_REGEX = /\A(PULL_REQUEST|ISSUE|DISCUSSION)/

    sig { returns(Repository) }
    attr_reader :current_repository

    sig { returns(GitHub::TokenScanning::Service::Token) }
    attr_reader :alert

    sig { params(alert: GitHub::TokenScanning::Service::Token, current_repository: ::Repository).void }
    def initialize(alert:, current_repository:)
      @alert = alert
      @current_repository = current_repository
    end

    sig { returns({ files: T::Array[GitHub::Proto::SecretScanning::Api::V2::TokenLocation], others: T::Array[GitHub::Proto::SecretScanning::Api::V2::TokenLocation] }) }
    memoize def locations
      locs = {
        files: [],
        others: []
      }

      alert.included_locations.each do |token|
        case token.location.content_type.to_s
        when "REPOSITORY_BLOB"
          locs[:files] << token.location
        when OTHER_LOCATIONS_REGEX
          locs[:others] << token.location
        end
      end

      locs
    end

    sig { returns(T::Array[MonolithTwirp::Copilotapi::Chat::V1::AlertFile]) }
    def related_files
      file_path_by_blob_oid = {}
      locations[:files]&.each do |location|
        file_path_by_blob_oid[location.blob_oid] = location.path
      end

      return [] if file_path_by_blob_oid.empty?

      current_repository.rpc.read_blobs(file_path_by_blob_oid.keys).filter_map do |raw_blob|
        next if raw_blob["binary"]
        path = file_path_by_blob_oid[raw_blob["oid"]]
        next unless path
        MonolithTwirp::Copilotapi::Chat::V1::AlertFile.new(
          path: path.dup.force_encoding("UTF-8").scrub!,
          contents: raw_blob["data"].dup.force_encoding("UTF-8").scrub!,
        )
      end
    end

    sig { returns(T.nilable(MonolithTwirp::Copilotapi::Chat::V1::SecretScanningAlert::Resolver)) }
    def resolver
      return nil unless alert.token.resolver_id.nil?
      user = ActiveRecord::Base.connected_to(role: :reading) { ::User.find_by(id: alert.token.resolver_id) }

      MonolithTwirp::Copilotapi::Chat::V1::SecretScanningAlert::Resolver.new(
        id: user.id,
        login: user.display_login,
        type: user.type,
      )
    end

    sig { returns(T.nilable(String)) }
    def remediation_steps
      # pulled from app/assets/modules/secret-scanning/components/show/remediation/Remediation.tsx
      is_inactive = alert.validity == :TOKEN_VALIDITY_INACTIVE || alert.validity == :TOKEN_VALIDITY_REVOKED

      steps = <<-STEPS
      1. #{is_inactive ? "Review the #{alert.label} through #{alert.token_type_provider} to ensure that the secret has not been used for unauthorized access. Learn more about #{alert.token_type_provider} tokens at this remediation url." : "Rotate the secret if it's in use to prevent breaking workflows."}
      STEPS

      unless is_inactive
        steps += <<-STEP
      2. #{alert.external_remediation_doc_url ? "Revoke this #{alert.label} through #{alert.token_type_provider} to prevent unauthorized access. Learn more about #{alert.token_type_provider} tokens at this remediation url." : "Revoke this #{alert.label} through the provider to prevent unauthorized access."}
      STEP
      end

      step_number = is_inactive ? 2 : 3
      steps += <<-STEP
      #{step_number}. Check security logs for potential breaches.
      STEP

      steps + <<-STEP
      #{step_number + 1}. Close the alert as revoked.
      STEP
    end

    sig { returns(T.nilable(String)) }
    def validity
      case alert.validity
      when :TOKEN_VALIDITY_UNKNOWN
        "unknown"
      when :TOKEN_VALIDITY_ACTIVE
        "active"
      when :TOKEN_VALIDITY_INACTIVE, :TOKEN_VALIDITY_REVOKED
        "inactive"
      else
        "unknown"
      end
    end

    sig { returns(MonolithTwirp::Copilotapi::Chat::V1::GetSecretScanningAlertResponse) }
    def payload
      MonolithTwirp::Copilotapi::Chat::V1::GetSecretScanningAlertResponse.new(
        alert: MonolithTwirp::Copilotapi::Chat::V1::SecretScanningAlert.new(
          number: alert.number,
          secret_type: alert.token_type,
          secret_type_label: alert.token.label,
          raw_secret: alert.raw_secret,
          resolution: alert.resolution,
          is_resolved: alert.resolved?,
          resolved_at: alert.resolved_at,
          resolved_by: resolver,
          remediation_steps: remediation_steps,
          external_remediation_url: alert.external_remediation_doc_url,
          validity: validity,
          repo_id: current_repository.id,
          url: "#{GitHub.url}/#{current_repository.name_with_display_owner}/security/secret-scanning/#{alert.number}",
          created_at: alert.token.created_at,
          related_files: related_files,
          file_locations: locations[:files]&.map do |location|
            MonolithTwirp::Copilotapi::Chat::V1::AlertLocation.new(
              path: location.path.dup.force_encoding("UTF-8").scrub!,
              start_line:  location.start_line,
              end_line: location.end_line,
              start_column: location.start_column,
              end_column: location.end_column,
            )
          end,
          other_locations: locations[:others]&.map do |location|
            type = location.content_type.match(OTHER_LOCATIONS_REGEX)[0].downcase

            MonolithTwirp::Copilotapi::Chat::V1::SecretScanningAlert::OtherLocation.new(
              type: type,
              number: location.content_number,
              url: location_url_for(type, location.content_number)
            )
          end
        )
      )
    end

    sig { params(type: String, number: Integer).returns(T.nilable(String)) }
    def location_url_for(type, number)
      resource_path = case type.to_sym
      when :issue
        "issues"
      when :pull_request
        "pull"
      when :discussion
        "discussions"
      end

      "#{GitHub.url}/#{current_repository.name_with_display_owner}/#{resource_path}/#{number}"
    end
  end
end
