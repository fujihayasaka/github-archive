# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Repository < ApplicationRecord::SecurityOverviewAnalytics
    extend T::Sig

    self.table_name = "soa_repositories"

    belongs_to :repository, class_name: "::Repository"
    belongs_to :organization, optional: true

    has_one :feature_status,
      -> { where(next_revision_date_id: Date::FUTURE_DATE_ID) },
      class_name: FeatureStatusRevision.name,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    has_many :feature_status_revisions,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    has_many :dependabot_alert_revisions,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    has_many :code_scanning_alert_revisions,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    has_many :code_scanning_pull_request_alerts,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    has_many :secret_scanning_alert_revisions,
      primary_key: :repository_id,
      inverse_of: :repository_metadata

    scope :with_feature_status, ->(feature, status_enabled:) {
      case feature
      when ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS
        joins(:feature_status_revisions).where(feature_status_revisions: {
          next_revision_date_id: Date::FUTURE_DATE_ID,
          dependabot_alerts_enabled: status_enabled
        })
      when ::SecurityCenter::SecurityFeatures::CODE_SCANNING
        joins(:feature_status_revisions).where(feature_status_revisions: {
          next_revision_date_id: Date::FUTURE_DATE_ID,
          code_scanning_enabled: status_enabled
        })
      when ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
        joins(:feature_status_revisions).where(feature_status_revisions: {
          next_revision_date_id: Date::FUTURE_DATE_ID,
          secret_scanning_enabled: status_enabled
        })
      else
        none
      end
    }

    # "scopes: false"
    # 1. To prevent Rails from generating scopes like "public" which would conflict with other already generated Rails functions
    # 2. We usually query with `where` instead of using scope functions
    enum :visibility, [:public, :private, :internal], scopes: false

    sig { returns(T::Array[Symbol]) }
    def fields_with_deviation
      return [:repo_not_found] if repository.nil?
      return [:repo_deleted] if repository&.deleted?

      output = T.let([], T::Array[Symbol])

      output << :business_id if business_id != BusinessResolver.resolve_for(T.must(repository))&.id
      output << :organization_id if organization_id > 0 && organization_id != repository&.owner_id
      output << :owner_id if owner_id != repository&.owner_id
      output << :owner_type if !owner_type.blank? && owner_type.upcase != repository&.owner&.type&.upcase
      output << :name if name != repository&.name
      output << :archived if archived? != repository&.archived?
      output << :visibility if visibility != repository&.visibility

      output
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.repository_metadata.deleted", batch_size)
        end
      end
    end
  end
end
