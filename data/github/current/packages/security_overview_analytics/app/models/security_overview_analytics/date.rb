# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Date < ApplicationRecord::SecurityOverviewAnalytics
    extend T::Sig
    self.table_name = "soa_dates"

    FUTURE_DATE_ID = 99991231
    RETENTION_DURATION = T.let(2.years, ActiveSupport::Duration)

    has_many :feature_status_revisions,
      class_name: SecurityOverviewAnalytics::FeatureStatusRevision.name,
      foreign_key: :date_id,
      inverse_of: :date
    has_many :last_feature_status_revisions,
      class_name: SecurityOverviewAnalytics::FeatureStatusRevision.name,
      foreign_key: :next_revision_date_id,
      inverse_of: :next_revision_date

    has_many :dependabot_alert_revisions,
      class_name: SecurityOverviewAnalytics::DependabotAlertRevision.name,
      foreign_key: :date_id,
      inverse_of: :date
    has_many :last_dependabot_alert_revisions,
      class_name: SecurityOverviewAnalytics::DependabotAlertRevision.name,
      foreign_key: :next_revision_date_id,
      inverse_of: :next_revision_date

    has_many :code_scanning_alert_revisions,
      class_name: SecurityOverviewAnalytics::CodeScanningAlertRevision.name,
      foreign_key: :date_id,
      inverse_of: :date
    has_many :last_code_scanning_alert_revisions,
      class_name: SecurityOverviewAnalytics::CodeScanningAlertRevision.name,
      foreign_key: :next_revision_date_id,
      inverse_of: :next_revision_date

    has_many :secret_scanning_alert_revisions,
      class_name: SecurityOverviewAnalytics::SecretScanningAlertRevision.name,
      foreign_key: :date_id,
      inverse_of: :date
    has_many :last_secret_scanning_alert_revisions,
      class_name: SecurityOverviewAnalytics::SecretScanningAlertRevision.name,
      foreign_key: :next_revision_date_id,
      inverse_of: :next_revision_date

    sig { params(date: ::Date).returns(Integer) }
    def self.id_from_date(date)
      date.strftime("%Y%m%d").to_i
    end

    sig { params(time: T.any(::Time, ActiveSupport::TimeWithZone)).returns(Integer) }
    def self.id_from_time(time)
      self.id_from_date(time.utc.to_date)
    end

    sig { returns(Integer) }
    def self.min_next_date_id
      self.id_from_time(RETENTION_DURATION.ago)
    end

    sig { params(time: T.any(::Time, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
    def self.within_retention_limit?(time)
      self.id_from_time(time) >= self.min_next_date_id
    end
  end
end
