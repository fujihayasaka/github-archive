# typed: true
# frozen_string_literal: true

module Repository::SecurityCenterDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!
  requires_ancestor { ::Repository }

  include SecretScanning::Features::FeatureFlagHelper

  included do
    T.bind(self, T.class_of(::Repository))
    has_many :repository_security_center_statuses, dependent: :delete_all
    has_many :security_center_alert_severities, dependent: :delete_all
    has_one :repository_security_center_config, dependent: :delete
  end

  def security_center_status_for_feature(feature_type)
    repository_security_center_statuses.to_a.find { |row| row.feature_type.eql?(feature_type) }
  end

  def security_center_config
    RepositorySecurityCenterConfig.where(repository: self).first
  end

  # The status of a single security center update
  class SecurityCenterUpdateStatus
    attr_accessor :scanning_status, :scanning_count, :scanning_date, :scanning_count_by_severity

    def initialize(scanning_status, scanning_count, scanning_date: nil, scanning_count_by_severity: nil)
      @scanning_status = scanning_status
      @scanning_count = scanning_count
      @scanning_date = scanning_date
      @scanning_count_by_severity = scanning_count_by_severity
    end
  end

  class SecurityCenterUpdateRepositoryConfiguration
    attr_accessor :name, :visibility

    def initialize(name, visibility)
      @name = name
      @visibility = visibility
    end
  end

  # Notifies security features in security center about a change to a repo
  # that affects the enrollment/eligibility of a security feature in that repo.
  def send_security_center_security_feature_repo_update(source_event = "")
    SecurityCenterUpdater.notify_security_features_for_repo(self, source_event: source_event)
  end

  class UnknownSecurityFeatureStatusError < StandardError
  end

  # Call this method to notify security center that something
  # changed for the specified security feature
  sig do
    params(
      feature_type: T.any(String, Symbol),
      source_event: String,
      skip_subfeature_updates: T::Boolean
    ).returns(T.untyped) # various returns, but no caller is listening
  end
  def security_center_notify(feature_type, source_event:, skip_subfeature_updates: false)
    if feature_type == SecurityCenter::SecurityFeatures::REPOSITORY_CONFIGURATION
      ActiveRecord::Base.connected_to(role: :writing) do
        return set_security_center_repository_configuration(source_event)
      end
    end

    status = T.let(nil, T.nilable(SecurityCenterUpdateStatus))
    subfeature_statuses = T.let({}, T::Hash[Symbol, T.nilable(SecurityCenterUpdateStatus)])
    case feature_type.to_s
    when SecurityCenter::SecurityFeatures::CODE_SCANNING
      status = code_scanning_security_center_status
      unless skip_subfeature_updates
        subfeature_statuses[:code_scanning_pr_reviews] = code_scanning_review_security_center_status(code_scanning_status: status)
        subfeature_statuses[:code_scanning_auto_codeql] = code_scanning_auto_codeql_security_center_status(actor)
      end
    when "code_scanning_pr_reviews"
      status = code_scanning_review_security_center_status
    when "code_scanning_auto_codeql"
      status = code_scanning_auto_codeql_security_center_status(actor)
    when SecurityCenter::SecurityFeatures::SECRET_SCANNING
      status = secret_scanning_security_center_status(actor)
      unless skip_subfeature_updates
        subfeature_statuses[:secret_scanning_push_protection] = push_protection_security_center_status
      end
    when "secret_scanning_push_protection"
      status = push_protection_security_center_status
    when SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS
      status = dependabot_alerts_security_center_status
      unless skip_subfeature_updates
        subfeature_statuses[:dependabot_security_updates] = security_updates_security_center_status
        unless feature_enabled?(:security_center_skip_dependabot_version_updates_status)
          subfeature_statuses[:dependabot_version_updates] = version_updates_security_center_status
        end
      end
    when "dependabot_security_updates"
      status = security_updates_security_center_status
    when "dependabot_version_updates"
      status = version_updates_security_center_status
    else
      Failbot.report(StandardError.new("Could not update security center for feature #{feature_type}"))
    end

    # If we could not get the main status we're after, raise an error so we retry
    if status.nil?
      # Some repositories will fail constantly and consistently. Add them to this feature flag.
      # Those repos aren't getting a correct/working experience anyway, so we just ignore them here.
      # Turboscan in particular will not automatically index (in Elasticsearch) a repo with
      # an abnormally large number of alerts, analyses, etc.
      return nil if feature_enabled?(:security_center_reconciliation_ignore_failure)

      # If we're not ignoring failures on this repository, raise an error so that we can try again.
      raise UnknownSecurityFeatureStatusError.new("Failed to get status for #{feature_type}")
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      set_security_center_status(source_event, feature_type, status, subfeature_statuses.compact)
    end

    status
  end

  # This method returns true if feature is enabled for the repository and alerts should show up in the UIs
  sig { params(security_feature: Symbol).returns(T.nilable(T::Boolean)) }
  def security_feature_visible?(security_feature)
    T.bind(self, ::Repository)

    case (security_feature)
    when :SECRET_SCANNING
      !deleted? && SecretScanning::Features::Repo::TokenScanning.new(self).enabled?
    when :SECRET_SCANNING_PUSH_PROTECTION
      SecretScanning::Features::Repo::PushProtection.new(self).enabled?(ignore_import: true)
    when :CODE_SCANNING
      code_scanning_usable?
    when :CODE_SCANNING_PR_REVIEWS
      code_scanning_review_security_center_status&.scanning_status == "enrolled"
    when :CODE_SCANNING_AUTO_CODEQL
      CodeScanning::AutoCodeql.new(self).enabled?
    when :DEPENDABOT_ALERTS
      SecurityProduct::VulnerabilityAlerts.new(self).enabled?
    when :DEPENDABOT_SECURITY_UPDATES
      SecurityProduct::VulnerabilityUpdates.new(self).enabled?
    when :ADVANCED_SECURITY
      SecurityProduct::AdvancedSecurity.new(self).enabled?
    else
      false
    end
  end

  # This method returns true if feature is fully configured
  # For all features besides code scanning this behaves same as security_feature_visible?
  def security_feature_configured?(security_feature)
    return security_feature_visible?(security_feature) unless security_feature == :CODE_SCANNING

    # nil means either default branch data not available or turboscan request failed
    # in both cases, return feature state as false
    !!turboscan_considers_code_scanning_enabled?
  end

  private

  sig { params(source_event: String).returns(T::Boolean) }
  def is_reconciliation_event?(source_event)
    SecurityCenter::OrganizationReconciliationJob.is_reconciliation_event?(source_event) ||
      SecurityCenter::OwnerReconciliationJob.is_reconciliation_event?(source_event) ||
      SecurityCenter::BusinessReconciliationJob.is_reconciliation_event?(source_event)
  end

  sig { params(source_event: String).returns(T.untyped) }
  def set_security_center_repository_configuration(source_event)
    GitHub.logger.with_named_tags(
      "gh.repo.id": self.id,
      "gh.repo.name": self.name,
      "gh.owner.id": self.owner_id,
      "gh.owner.login": self.owner_display_login,
      "gh.owner.type": self.owner_type,
      "gh.business.id": self.business_id,
      "gh.org.id": self.owner_id, # assumed to be org because we only work with orgs in RepositorySecurityCenterConfig
      "gh.org.login": self.owner_display_login, # assumed to be org because we only work with orgs in RepositorySecurityCenterConfig
      "gh.security_center.feature_type": "repository_configuration",
      "gh.security_center.source_event": source_event,
    ) do
      report_deviations = is_reconciliation_event?(source_event)

      RepositorySecurityCenterConfig.throttle do
        current_config = self.repository_security_center_config

        if report_deviations
          deviations = []

          if current_config.nil?
            deviations << "record_missing"
          else
            deviations << "name" if current_config.name != self.name
            deviations << "owner_id" if current_config.owner_id != self.owner_id
            deviations << "owner_type" unless current_config.owner_type.casecmp?(self.owner_type)
            deviations << "business_id" if current_config.business_id != self.business_id
            deviations << "visibility" if current_config.visibility != self.visibility
            deviations << "archived" if current_config.archived != self.archived?
            deviations << "ghas_enabled" if current_config.ghas_enabled != self.advanced_security_enabled?
            deviations << "last_push" if current_config.last_push&.to_i != self.pushed_at&.to_i # ignore fractional seconds
          end

          if deviations.any?
            deviations.sort!
            GitHub.logger.warn(
              "Deviation detected in repository configuration",
              "gh.security_center.deviations": deviations,
              )
            GitHub.dogstats.increment("security_center.reconciliation.deviation.count", tags: [
              "source_event:#{source_event}",
              "feature_type:repository_configuration",
              *deviations.map { |d| "deviation:#{d}" },
            ])
          end
        end

        log_message = "#{current_config.present? ? "Updating" : "Creating"} repository config"
        GitHub.logger.info(log_message, "code.function": __method__)

        if current_config.present?
          current_config.update!(
            owner_id: self.owner_id,
            owner_type: self.owner_type,
            business_id: self.business_id,
            name: self.name,
            visibility: self.visibility,
            archived: self.archived?,
            last_push: self.pushed_at,
            ghas_enabled: self.advanced_security_enabled?
          )
        else
          now = Time.now
          # rubocop:disable GitHub/UpsertAll
          RepositorySecurityCenterConfig.upsert_all(
            [{
              repository_id: self.id,
              owner_id: self.owner_id,
              owner_type: self.owner_type,
              business_id: self.business_id,
              name: self.name,
              visibility: self.visibility,
              archived: self.archived?,
              created_at: now,
              updated_at: now,
              last_push: self.pushed_at,
              ghas_enabled: self.advanced_security_enabled?
            }],
            update_only: [
              :updated_at,
              :owner_id,
              :owner_type,
              :business_id,
              :name,
              :visibility,
              :archived,
              :last_push,
              :ghas_enabled
            ]
          )
        end
      end
    end
  end

  sig do
    params(
      source_event: String,
      feature_type: T.any(String, Symbol),
      feature_status: SecurityCenterUpdateStatus,
      subfeature_statuses: T::Hash[Symbol, SecurityCenterUpdateStatus],
    ).returns(T.untyped)
  end
  def set_security_center_status(
    source_event,
    feature_type,
    feature_status,
    subfeature_statuses
  )
    GitHub.logger.with_named_tags(
      "gh.repo.id": self.id,
      "gh.repo.name": self.name,
      "gh.owner.id": self.owner_id,
      "gh.owner.login": self.owner_display_login,
      "gh.business.id": self.business_id,
      "gh.org.id": self.owner_id, # assumed to be org because we only work with orgs in RepositorySecurityCenterStatus
      "gh.org.login": self.owner_display_login, # assumed to be org because we only work with orgs in RepositorySecurityCenterStatus
      "gh.security_center.feature_type": feature_type,
      "gh.security_center.source_event": source_event,
    ) do
      report_deviations = is_reconciliation_event?(source_event)

      RepositorySecurityCenterStatus.throttle do
        current_status = self.repository_security_center_statuses.find_by(feature_type: feature_type)

        if report_deviations
          deviations = []

          if current_status.nil?
            deviations << "record_missing"
          else
            deviations << "scanning_count" if current_status.scanning_count != feature_status.scanning_count
            deviations << "scanning_status" if current_status.scanning_status != feature_status.scanning_status
          end

          if deviations.any?
            deviations.sort!
            GitHub.logger.warn(
              "Deviation detected in feature status",
              "gh.security_center.deviations": deviations,
            )
            GitHub.dogstats.increment("security_center.reconciliation.deviation.count", tags: [
              "source_event:#{source_event}",
              "feature_type:#{feature_type}",
              *deviations.map { |d| "deviation:#{d}" },
            ])
          end
        end

        log_message = "#{current_status.present? ? "Updating" : "Creating"} feature status"
        GitHub.logger.info(log_message, "code.function": __method__)

        if current_status.present?
          current_status.update!(
            owner_id: self.owner_id,
            business_id: self.business_id,
            scanning_status: feature_status.scanning_status,
            scanning_count: feature_status.scanning_count,
            scanned_at: feature_status.scanning_date
          )
        else
          now = Time.now
          # rubocop:disable GitHub/UpsertAll
          RepositorySecurityCenterStatus.upsert_all(
            [{
              repository_id: self.id,
              created_at: now,
              updated_at: now,
              owner_id: self.owner_id,
              business_id: self.business_id,
              feature_type: feature_type,
              scanning_status: feature_status.scanning_status,
              scanning_count: feature_status.scanning_count,
              scanned_at: feature_status.scanning_date
            }],
            update_only: [
              :updated_at,
              :owner_id,
              :business_id,
              :scanning_status,
              :scanning_count,
              :scanned_at
            ]
          )
        end

        # Updates subfeature statuses
        subfeature_statuses.each do |subfeature, subfeature_status|
          GitHub.logger.with_named_tags("gh.security_center.feature_type": subfeature) do
            current_subfeature_status = self.repository_security_center_statuses.find_by(feature_type: subfeature)

            if report_deviations
              deviations = []

              if current_subfeature_status.nil?
                deviations << "record_missing"
              else
                deviations << "scanning_status" if current_subfeature_status.scanning_status != subfeature_status.scanning_status
              end

              if deviations.any?
                deviations.sort!
                GitHub.logger.warn(
                  "Deviation detected in feature status",
                  "gh.security_center.deviations": deviations,
                )
                GitHub.dogstats.increment("security_center.reconciliation.deviation.count", tags: [
                  "source_event:#{source_event}",
                  "feature_type:#{subfeature}",
                  *deviations.map { |d| "deviation:#{d}" },
                ])
              end
            end

            log_message = "#{current_subfeature_status.present? ? "Updating" : "Creating"} feature status"
            GitHub.logger.info(log_message, "code.function": __method__)

            if current_subfeature_status.present?
              current_subfeature_status.update!(
                owner_id: self.owner_id,
                business_id: self.business_id,
                scanning_status: subfeature_status.scanning_status,
                scanning_count: 0,
                scanned_at: nil
              )
            else
              now = Time.now
              # rubocop:disable GitHub/UpsertAll
              RepositorySecurityCenterStatus.upsert_all(
                [{
                  repository_id: self.id,
                  created_at: now,
                  updated_at: now,
                  owner_id: T.must(self.owner).id,
                  business_id: self.business_id,
                  feature_type: subfeature.to_s,
                  scanning_status: subfeature_status.scanning_status,
                  scanning_count: 0,
                  scanned_at: nil
                }],
                update_only: [
                  :updated_at,
                  :owner_id,
                  :business_id,
                  :scanning_status,
                  :scanning_count,
                  :scanned_at,
                ]
              )
            end
          end
        end

        # scanning_count_by_severity only contains open alerts; it won't have severities with a count of 0
        # Therefore we need to cover the case where a user previously had alerts of a particular severity,
        # but resolved those alerts, and therefore we shouldn't have a status for them anymore.
        severities = feature_status.scanning_count_by_severity&.keys
        extra_severities = SecurityCenterAlertSeverity.where(repository_id: self.id, feature_type: feature_type).where.not(severity: severities)
        extra_severities.each do |extra_severity|
          GitHub.logger.with_named_tags("gh.security_center.severity": extra_severity.severity) do
            if report_deviations
              GitHub.logger.warn(
                "Deviation detected in feature severity status",
                "gh.security_center.deviations": ["record_exists"],
              )
              GitHub.dogstats.increment("security_center.reconciliation.deviation.severitycount", tags: [
                "source_event:#{source_event}",
                "feature_type:#{feature_type}",
                "severity:#{extra_severity.severity}",
                "deviation:record_exists",
              ])
            end

            extra_severity.destroy!
          end
        end

        # Updates remaining severities statuses
        feature_status.scanning_count_by_severity&.each do |severity, count|
          GitHub.logger.with_named_tags("gh.security_center.severity": severity) do
            current_alert_severity = self.security_center_alert_severities.find_by(feature_type: feature_type, severity: severity)

            if report_deviations
              deviations = []

              if current_alert_severity.nil?
                deviations << "record_missing"
              else
                deviations << "alert_count" if current_alert_severity.alert_count != count
              end

              if deviations.any?
                deviations.sort!
                GitHub.logger.warn(
                  "Deviation detected in feature severity status",
                  "gh.security_center.deviations": deviations,
                )
                GitHub.dogstats.increment("security_center.reconciliation.deviation.severitycount", tags: [
                  "source_event:#{source_event}",
                  "feature_type:#{feature_type}",
                  "severity:#{severity}",
                  *deviations.map { |d| "deviation:#{d}" },
                ])
              end
            end

            log_message = "#{current_alert_severity.present? ? "Updating" : "Creating"} feature severity status"
            GitHub.logger.info(log_message, "code.function": __method__)

            if current_alert_severity.present?
              current_alert_severity.update!(alert_count: count)
            else
              now = Time.now
              # rubocop:disable GitHub/UpsertAll
              SecurityCenterAlertSeverity.upsert_all(
                [{
                  repository_id: self.id,
                  created_at: now,
                  updated_at: now,
                  feature_type: feature_type,
                  severity: severity,
                  alert_count: count,
                }],
                update_only: [
                  :updated_at,
                  :alert_count,
                ]
              )
            end
          end
        end
      end
    end
  end

  def secret_scanning_security_center_status(actor)
    T.bind(self, ::Repository)
    if SecretScanning::Features::Repo::TokenScanning.new(self).feature_available?
      if !GitHub.enterprise? && public? && !SecretScanning::Features::Repo::TokenScanning.new(self).enabled?
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0)
      elsif SecretScanning::Features::Repo::TokenScanning.new(self).enabled?
        req = {
          repository_id: self.id,
          feature_flags: get_tokens_api_feature_flags(self),
        }
        count = GitHub::TokenScanning::Service::Client.new(actor).get_token_counts(req)&.data&.unresolved_count
        return if count.nil? # request failed

        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", count)
      else
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0)
      end
    else
      Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0)
    end
  end
end
