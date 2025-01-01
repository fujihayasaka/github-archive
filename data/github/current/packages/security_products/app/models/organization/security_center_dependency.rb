# typed: strict
# frozen_string_literal: true

module Organization::SecurityCenterDependency
  extend ActiveSupport::Concern

  sig { returns(T::Boolean) }
  def trigger_security_center_reconciliation
    T.bind(self, ::Organization)
    needs_backfill = T.let(false, T::Boolean)

    if self.repositories.any?
      needs_backfill = repository_security_center_configs.empty?
      unless needs_backfill
        # only check status counts if configs matched
        expected_features = SecurityCenter::SecurityFeatures.visible_features(self)
          .flat_map { |f| [f] + RepositorySecurityCenterStatus.subfeatures_for(f) }
          .map(&:to_s)

        # in case of GHES, it's possible for there to be no visible features
        if expected_features.any?
          # for performance reasons, querying each feature_type individually is much faster
          # for organizations with many repositories, otherwise mysql needs to scan the entire
          # index even though it should be able to short-circuit once it finds a hit for feature_type
          feature_type_subquery = expected_features.map do |feature_type|
            "(%{subquery})" % {
              subquery: repository_security_center_statuses
                .where(feature_type: feature_type)
                .select(:feature_type)
                .limit(1)
                .to_sql
            }
          end.join(" UNION ")

          actual_features = RepositorySecurityCenterStatus.connection.select_values(Arel.sql("SELECT feature_type FROM (#{feature_type_subquery}) AS feature_types"))

          needs_backfill ||= (expected_features - actual_features).any?
        end
      end
    else
      needs_backfill = repository_security_center_configs.any? ||
        repository_security_center_statuses.any?
    end

    # If we detected a deviation in the expected amount of data, clear the
    # reconciliation lock to effectively "force" reconciliation to run.
    if needs_backfill
      GitHub.logger.info("Clearing reconciliation lock",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.org.id": self.id,
        "gh.org.login": self.display_login,
      )
      ::SecurityCenter::OwnerReconciliationJob::KvHelper.new(self.id).session_lock = nil
      GitHub.dogstats.increment("security_center.deviation.count", tags: ["scope:org"])
    end

    # enqueue will noop unless
    #  - it has been 7+ days since the last reconciliation (via org event or this backfill)
    #  - we just cleared the lock above
    source_event = ::SecurityCenter::OwnerReconciliationJob::RECONCILIATION_EVENT
    source_event = ::SecurityCenter::OwnerReconciliationJob::BACKFILL_EVENT if needs_backfill

    ::SecurityCenter::OwnerReconciliationJob.perform_later(owner_id: self.id, source_event: source_event)

    # only show the banner if we detected deviation (rare)
    needs_backfill
  rescue => exception # rubocop:disable Lint/RescueException
    # Reports exception but does not block caller if fails to attempt the backfill
    Failbot.report(exception, {
      "gh.org.id": self.id,
    })
    needs_backfill
  end

  sig { returns(ActiveRecord::Relation) }
  def security_center_repo_config_status_scope
    T.bind(self, ::Organization)

    RepositorySecurityCenterConfig
      .where(owner_id: self.id)
      .joins(%{
        LEFT JOIN repository_security_center_statuses
          ON repository_security_center_statuses.repository_id = repository_security_center_configs.repository_id
          AND repository_security_center_statuses.owner_id = repository_security_center_configs.owner_id
        })
  end
end
