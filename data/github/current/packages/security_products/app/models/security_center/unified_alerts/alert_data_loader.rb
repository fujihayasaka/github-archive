# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module AlertDataLoader
      extend T::Sig
      extend T::Helpers

      # Secret scanning utilities
      include ::TextHelper
      include ::SecretScanning::Encryption::EncryptedSecretsHelper
      include ::GitHub::TokenScanning::SecretScanningHelper
      include ::ScanningHelper
      include ::SecretScanning::Features::FeatureFlagHelper

      MAX_RETRIES = 3

      abstract!

      requires_ancestor { ListDataQuery }

      private

      sig { params(alerts: T::Array[ListDataQuery::AlertData]).void }
      def hydrate_alerts_data!(alerts)
        repository_ids = T.let([], T::Array[Integer])
        dependabot_alerts = T.let([], T::Array[ListDataQuery::AlertData])
        code_scanning_alerts = T.let([], T::Array[ListDataQuery::AlertData])
        secret_scanning_alerts = T.let([], T::Array[ListDataQuery::AlertData])

        alerts.each do |alert|
          repository_ids << alert[:repository_id]
          dependabot_alerts << alert if alert[:feature_type] == SecurityFeatures::DEPENDABOT_ALERTS
          code_scanning_alerts << alert if alert[:feature_type] == SecurityFeatures::CODE_SCANNING
          secret_scanning_alerts << alert if alert[:feature_type] == SecurityFeatures::SECRET_SCANNING
        end

        repositories_by_id = ::Repository.where(id: repository_ids).includes(:owner).map do |r|
          [T.must(r.id), r]
        end.to_h

        alerts.each do |alert|
          repository = T.must(repositories_by_id[alert[:repository_id]])
          alert[:repository_name] = repository.name
          alert[:repository_visibility] = repository.visibility
          alert[:repository_href] = repository.permalink
          alert[:repository_type_icon] = repository.repo_type_icon

          # Build the href for the alert's show page.
          # We have enough to do this even if the hydrate request fails.
          alert[:alert_href] = alert_href(repository, alert[:feature_type], alert[:alert_number])
        end

        hydrate_dependabot_alerts!(dependabot_alerts)
        hydrate_code_scanning_alerts!(code_scanning_alerts)
        hydrate_secret_scanning_alerts!(secret_scanning_alerts, repositories_by_id)
      end

      sig do
        params(
          repository: ::Repository,
          feature_type: String,
          alert_number: Integer
        ).returns(String)
      end
      def alert_href(repository, feature_type, alert_number)
        href_args = {
          user_id: repository.owner_display_login,
          repository: repository.name,
          number: alert_number,
        }
        case feature_type
        when SecurityFeatures::DEPENDABOT_ALERTS
          UrlHelpers.repository_alert_path(*T.unsafe(href_args.values))
        when SecurityFeatures::CODE_SCANNING
          UrlHelpers.repository_code_scanning_result_path(*T.unsafe(href_args.values))
        when SecurityFeatures::SECRET_SCANNING
          UrlHelpers.repository_react_alerts_show_path(*T.unsafe(href_args.values))
        end
      end

      sig { params(alerts: T::Array[ListDataQuery::AlertData]).void }
      def hydrate_dependabot_alerts!(alerts)
        return unless alerts.present?

        GitHub.dogstats.distribution_time(
          "security_center.unified_alerts.hydrate_alerts_data.dist",
          tags: ["feature_type:#{SecurityFeatures::DEPENDABOT_ALERTS}"]
        ) do
          alert_selector_query_string = alerts.map { |alert| "(#{alert[:repository_id]},#{alert[:alert_number]})" }.join(",")
          alerts_data_by_repo_number = ::RepositoryVulnerabilityAlert
            .where("(repository_id, number) IN (#{Arel.sql(alert_selector_query_string)})")
            .includes(:vulnerability, :vulnerable_version_range)
            .map { |data| [[data.repository_id, T.must(data.number)], data] }
            .to_h

          alerts.each do |alert|
            alert_data = alerts_data_by_repo_number[[alert[:repository_id], alert[:alert_number]]]
            next unless alert_data.present?

            alert[:alert_title] = alert_data.title
            alert[:alert_severity] = alert_data.severity == "moderate" ? "medium" : alert_data.severity
            alert[:alert_dependency_scope] = alert_data.dependency_scope
            alert[:alert_package_name] = alert_data.package_name
            alert[:alert_ecosystem] = alert_data.ecosystem
            alert[:alert_location] = reverse_truncate_path(alert_data.vulnerable_manifest_path, 24)
            alert[:alert_resolved] = alert_data.state == "closed"
            alert[:alert_resolution] = alert_data.resolution
            alert[:alert_updated_at] = alert_data.last_state_change_at
          end
        end
      end

      sig { params(alerts: T::Array[ListDataQuery::AlertData]).void }
      def hydrate_code_scanning_alerts!(alerts)
        return unless alerts.present?

        GitHub.dogstats.distribution_time(
          "security_center.unified_alerts.hydrate_alerts_data.dist",
          tags: ["feature_type:#{SecurityFeatures::CODE_SCANNING}"]
        ) do
          alerts.each do |alert|
            response_data = T.let(request_with_retry do
              # TODO: need to follow up the progress of fixing alert_number in production
              GitHub::Turboscan.alert(
                repository_id: alert[:repository_id],
                number: alert[:alert_number],
              )
            end, T.nilable(::Turboscan::Proto::AlertResponse))
            alert_data = response_data&.result
            next if alert_data.nil?

            alert[:alert_title] = alert_data.rule&.short_description || strip_tags_and_collapse_whitespace(GitHub::Goomba::MarkdownPipeline.to_html(alert_data.message_text))
            alert[:alert_tool] = alert_data.tool&.name
            alert[:alert_severity] =
              if alert_data.security_severity != :NO_SECURITY_SEVERITY
                alert_data.security_severity.to_s.titleize
              else
                alert_data.rule_severity.to_s.titleize
              end
            alert[:alert_classifications] = alert_data.most_recent_instance&.classification&.map { |classification| classification.capitalize } || []
            alert[:alert_location] = if alert_data.most_recent_instance&.location
              location = reverse_truncate_path(alert_data.most_recent_instance&.location&.file_path, 24)
              location += ":#{alert_data.most_recent_instance&.location&.start_line}"
              location
            end
            alert[:alert_resolved] = !!alert_data.resolved_at&.to_time
            alert[:alert_resolution] = alert_data.resolution
            alert[:alert_updated_at] = alert_data.resolved_at&.to_time || alert_data.created_at&.to_time
          end
        end
      end

      sig do
        params(
          alerts: T::Array[ListDataQuery::AlertData],
          repositories_by_id: T::Hash[Integer, ::Repository]
        ).void
      end
      def hydrate_secret_scanning_alerts!(alerts, repositories_by_id)
        return unless alerts.present?

        GitHub.dogstats.distribution_time(
          "security_center.unified_alerts.hydrate_alerts_data.dist",
          tags: ["feature_type:#{SecurityFeatures::SECRET_SCANNING}"]
        ) do
          alerts.each do |alert|
            response_data = T.let(request_with_retry do
              GitHub::TokenScanning::Service::Client.new(nil).get_token(
                repository_id: alert[:repository_id],
                token_id: alert[:alert_number]
              )
            end, T.nilable(::GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse))
            token_data = response_data&.token
            return if token_data.nil?

            repository = T.must(repositories_by_id[alert[:repository_id]])
            alert_data = GitHub::TokenScanning::Service::Client.wrap_token(token_data, repository)
            set_raw_secret_from_encrypted_secret(alert_data)
            if alert_data.raw_secret.nil?
              SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert_data)
            end

            alert[:alert_title] = alert_data.label
            alert[:alert_severity] = "critical"
            alert[:alert_raw_secret] = SecretScanning::Util::RawSecret.token_literal_from_secret(alert_data.raw_secret) || SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE
            alert[:alert_active] = alert_data.validity_active?
            alert[:alert_is_custom_pattern] = alert_data.is_custom?
            alert[:alert_resolved] = alert_data.resolved?
            alert[:alert_resolution] = alert_data.resolution
            alert[:alert_updated_at] = alert_data.last_modified_at
            alert[:alert_location] =
              case alert_data.first_location&.content_type
              when :REPOSITORY_BLOB, :WIKI_BLOB
                location = reverse_truncate_path(alert_data.first_location.path, 24)
                location += ":#{alert_data.first_location.start_line}" unless alert_data.found_in_archive?
                location
              when :ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT
                issue = alert_data.repository.issues.find_by(id: alert_data.first_location.content_id)
                if issue.present? && issue.pull_request_id.present?
                  "pull request ##{alert_data.first_location.content_number}"
                else
                  "issue ##{alert_data.first_location.content_number}"
                end
              when :DISCUSSION_TITLE, :DISCUSSION_BODY, :DISCUSSION_COMMENT
                "discussion ##{alert_data.first_location.content_number}"
              when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY, :PULL_REQUEST_COMMENT, :PULL_REQUEST_REVIEW, :PULL_REQUEST_REVIEW_COMMENT, :PULL_REQUEST_TIMELINE_COMMENT
                "pull request ##{alert_data.first_location.content_number}"
              end
          end
        end
      end

      sig do
        params(
          num_of_retries: Integer,
          block: T.proc.returns(T.untyped)
        ).returns(T.untyped)
      end
      def request_with_retry(num_of_retries: MAX_RETRIES, &block)
        retry_count = 0

        while retry_count <= num_of_retries
          response = yield
          response_data = response.try(:data)

          if response.nil? || response_data.nil? || response.error.present?
            err_msg = response&.error&.msg || "Failed to get alert"
            Failbot.report("#{err_msg}. number of retries: #{retry_count}/#{num_of_retries}")
            retry_count += 1
          else
            return response_data
          end
        end

        nil
      end
    end
  end
end
