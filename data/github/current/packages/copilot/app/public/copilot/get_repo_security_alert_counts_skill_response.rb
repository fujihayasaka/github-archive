# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilotapi-chat"

module Copilot
  class GetRepoSecurityAlertCountsSkillResponse
    include GitHub::Memoizer

    CODE_SCANNING = T.let(::SecurityCenter::SecurityFeatures::CODE_SCANNING, String)
    DEPENDABOT_ALERTS = T.let(::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, String)
    SECRET_SCANNING = T.let(::SecurityCenter::SecurityFeatures::SECRET_SCANNING, String)

    SEVERITIES = T.let(Set.new(%w[critical high low medium]), T::Set[String])

    sig { returns(::User) }; attr_reader :user
    sig { returns(::Repository) }; attr_reader :repo

    sig { params(user: ::User, repo: ::Repository).void }
    def initialize(user:, repo:)
      @user = user
      @repo = repo
    end

    sig { returns(::MonolithTwirp::Copilotapi::Chat::V1::GetRepoSecurityAlertCountsResponse) }
    memoize def payload
      res = ::MonolithTwirp::Copilotapi::Chat::V1::GetRepoSecurityAlertCountsResponse.new(repo_id: repo.id)

      feature_status_summary = ::SecurityOverviewAnalytics::FeatureStatus.find_by(repository_id: repo.id)
      return res if feature_status_summary.nil?

      if accessible_feature_types.include?(CODE_SCANNING)
        res.code_scanning = ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsCodeScanning.new(
          alert_counts: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsAlertCounts.new(
            critical: feature_status_summary.code_scanning_alerts_critical_count,
            high: feature_status_summary.code_scanning_alerts_high_count,
            medium: feature_status_summary.code_scanning_alerts_medium_count,
            low: feature_status_summary.code_scanning_alerts_low_count,
            informational: feature_status_summary.code_scanning_alerts_info_count,
          ),
          enablement_status: status_display_name(feature_status_summary.code_scanning_alerts_status),
          name: coverage_display_name(:code_scanning, :code_scanning),
          sub_features: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsCodeScanningSubFeatures.new(
            pull_request_reviews: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSubFeatureSummary.new(
              enablement_status: status_display_name(feature_status_summary.code_scanning_pr_reviews_status),
              name: coverage_display_name(:code_scanning, :code_scanning_pr_reviews),
            ),
            codeql_default_setup: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSubFeatureSummary.new(
              enablement_status: status_display_name(feature_status_summary.code_scanning_auto_codeql_status),
              name: coverage_display_name(:code_scanning, :code_scanning_auto_codeql),
            ),
          ),
        )
      end

      if accessible_feature_types.include?(DEPENDABOT_ALERTS)
        res.dependabot = ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsDependabot.new(
          alert_counts: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsAlertCounts.new(
            critical: feature_status_summary.dependabot_alerts_critical_count,
            high: feature_status_summary.dependabot_alerts_high_count,
            medium: feature_status_summary.dependabot_alerts_medium_count,
            low: feature_status_summary.dependabot_alerts_low_count,
          ),
          enablement_status: status_display_name(feature_status_summary.dependabot_alerts_status),
          name: coverage_display_name(:dependabot_alerts, :dependabot_alerts),
          sub_features: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsDependabotSubFeatures.new(
            security_updates: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSubFeatureSummary.new(
              enablement_status: status_display_name(feature_status_summary.dependabot_security_updates_status),
              name: coverage_display_name(:dependabot_alerts, :dependabot_security_updates),
            ),
            version_updates: nil, # https://github.com/github/security-center/issues/6192
          )
        )
      end

      if accessible_feature_types.include?(SECRET_SCANNING)
        res.secret_scanning = ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSecretScanning.new(
          alert_counts: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsAlertCounts.new(
            # All secret scanning alerts are considered critical.
            critical: feature_status_summary.secret_scanning_alerts_total_count,
          ),
          enablement_status: status_display_name(feature_status_summary.secret_scanning_alerts_status),
          name: coverage_display_name(:secret_scanning, :secret_scanning),
          sub_features: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSecretScanningSubFeatures.new(
            push_protection: ::MonolithTwirp::Copilotapi::Chat::V1::RepoSecurityAlertCountsSubFeatureSummary.new(
              enablement_status: status_display_name(feature_status_summary.secret_scanning_push_protection_status),
              name: coverage_display_name(:secret_scanning, :secret_scanning_push_protection),
            ),
          )
        )
      end

      res
    end

    sig { returns(T::Array[String]) }
    memoize def accessible_feature_types
      feature_types = []

      if ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance? && repo.can_view_vulnerability_alerts?(user)
        feature_types << DEPENDABOT_ALERTS.to_s
      end

      if ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance? && repo.code_scanning_readable_by?(user)
        feature_types << CODE_SCANNING.to_s
      end

      if ::SecurityCenter::SecurityFeatures.secret_scanning_enabled_for_instance? && ::SecretScanning::Features::Repo::TokenScanning.new(repo).view_alerts_allowed?(user)
        feature_types << SECRET_SCANNING.to_s
      end

      subfeatures = T.let([], T::Array[String])
      feature_types.each do |feature_type|
        subfeatures += ::RepositorySecurityCenterStatus.subfeatures_for(feature_type.to_sym).map(&:to_s)
      end

      feature_types + subfeatures
    end

    sig { params(feature: Symbol, coverage: Symbol).returns(String) }
    def coverage_display_name(feature, coverage)
      feature_name = RepositorySecurityCenterStatus.feature_display_name_for(feature)
      coverage_name = RepositorySecurityCenterStatus.coverage_display_name_for(coverage)
      return "CodeQL #{coverage_name.downcase}" if coverage == :code_scanning_auto_codeql
      "#{feature_name} #{coverage_name}".downcase.capitalize
    end

    sig { params(status: T.nilable(String)).returns(T.nilable(String)) }
    def status_display_name(status)
      status_name = \
        case status
        when "ENABLED"; "enrolled"
        when "NOT_ENABLED"; "not_enrolled"
        else status
        end
      status_name
    end
  end
end
