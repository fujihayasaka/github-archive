# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilotapi-chat"

module Copilot
  class GetCodeScanningAlertSkillResponse
    include GitHub::Memoizer

    sig { returns(Repository) }
    attr_reader :current_repository

    sig { returns(Turboscan::Proto::AlertResponse) }
    attr_reader :alert

    sig { params(alert: Turboscan::Proto::AlertResponse, current_repository: ::Repository).void }
    def initialize(alert:, current_repository:)
      @alert = alert
      @current_repository = current_repository
    end

    sig { returns(String) }
    memoize def state
      if alert.result&.is_fixed
        "fixed"
      else
        (alert.result&.resolution != :NO_RESOLUTION ? "dismissed" : "open")
      end
    end

    sig { returns(String) }
    memoize def severity
      if alert.result&.security_severity != :NO_SECURITY_SEVERITY
        alert.result&.security_severity.to_s.downcase
      else
        alert.result&.rule_severity.to_s.downcase
      end
    end

    sig { returns(T.nilable(String)) }
    memoize def commit_oid
      current_repository.refs.read(alert.ref_name_bytes.b)&.target_oid
    end

    sig { returns(T::Array[::Turboscan::Proto::Location]) }
    memoize def locations
      [alert.result&.most_recent_instance&.location, *alert.related_locations.map(&:location)].compact
    end

    sig { returns(T::Array[MonolithTwirp::Copilotapi::Chat::V1::AlertFile]) }
    def related_files
      return [] if commit_oid.nil?

      file_paths = locations.map(&:file_path).uniq
      blob_paths_with_commit = file_paths.map { |path| [commit_oid, path] }

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

    sig { returns(T.nilable(String)) }
    def resolved_by_login
      resolver_id = alert.result&.resolver_id
      return unless resolver_id.present?
      ::User.where(id: resolver_id).pick(:login)
    end

    sig { returns(MonolithTwirp::Copilotapi::Chat::V1::GetCodeScanningAlertResponse) }
    def payload
      MonolithTwirp::Copilotapi::Chat::V1::GetCodeScanningAlertResponse.new(
        alert: MonolithTwirp::Copilotapi::Chat::V1::CodeScanningAlert.new(
          title: alert.result&.rule&.short_description,
          number: alert.result&.number,
          tags: alert.rule_tags.to_a,
          severity: severity,
          description: alert.result&.rule&.full_description,
          help: alert.rule_help,
          state: state,
          ref: alert.ref_name_bytes.dup.force_encoding("UTF-8").scrub!,
          related_files: related_files,
          related_locations: locations.map do |location|
            MonolithTwirp::Copilotapi::Chat::V1::AlertLocation.new(
              path: location.file_path.dup.force_encoding("UTF-8").scrub!,
              start_line:  location.start_line,
              end_line: location.end_line,
              start_column: location.start_column,
              end_column: location.end_column,
            )
          end,
          repo_id: current_repository.id,
          url: UrlHelpers.repository_code_scanning_result_path(current_repository.owner, current_repository, number: alert.result&.number),
          created_at: alert.result&.created_at,
          fixed_at: alert.result&.fixed_at,
          resolved_at: alert.result&.resolved_at,
          resolution_note: alert.result&.resolution_note,
          resolved_by_login: resolved_by_login,
        )
      )
    end
  end
end
