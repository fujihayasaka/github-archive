# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class InsightsEntityBatchHydroMessageJob < ::HydroMessageJob
    extend T::Helpers
    include GitHub::Memoizer
    include LifecycleEventHandler

    abstract!

    set_callback :perform, :around, :process_batch

    retry_on_dirty_exit

    resolve_tenant_context do |message|
      entities = (message[:entities_updated] || []) + (message[:entities_deleted] || [])
      repo_id = entities.map { |e| e.dig(:data, "repository_id") }.compact.first
      ::Repositories::Public.resolve_tenant(id: repo_id)
    end

    BATCH_SIZE = T.let(100, Integer)

    sig { override.returns(T::Array[String]) }
    def all_stats_tags
      super.concat([
        "source_event:#{source_event}",
        "target_entity_type:#{target_entity_type}",
        "entity_type:#{entity_type}",
      ]).compact
    end

    sig { override.returns(Integer) }
    def repository_id
      # This job operates on a batch of alerts, which may not all be from the same repository.
      raise NotImplementedError
    end

    private

    sig { params(block: T.proc.void).void }
    def process_batch(&block)
      if has_expected_entity_type?
        yield
      else
        GitHub.dogstats.increment(
          "security_center.insights_entity_batch.skipped",
          tags: all_stats_tags + ["reason:unexpected_entity_type"]
        )
      end
    end

    sig { abstract.returns(String) }
    def target_entity_type; end

    sig { abstract.returns(String) }
    def feature_type; end

    sig { abstract.returns(String) }
    def source_event; end

    sig { returns(String) }
    memoize def entity_type
      message[:entity]
    end

    sig { returns(T::Boolean) }
    memoize def has_expected_entity_type?
      entity_type == target_entity_type
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    memoize def entities_updated
      payload = message[:entities_updated]
      return [] if payload.blank?
      payload.map { |m| m[:data] }
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    memoize def entities_deleted
      payload = message[:entities_deleted]
      return [] if payload.blank?
      payload.map { |m| m[:data] }
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.job.target_entity_type": target_entity_type,
        "gh.security_center.job.entity_type": entity_type,
        "gh.security_center.job.repository_ids": repository_ids.join(","),
        "gh.security_center.job.source_event": source_event,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { returns(T::Array[::Repository]) }
    memoize def repositories_to_process
      out = T.let([], T::Array[::Repository])
      repository_ids.each do |id|
        repository = repositories_lookup[id]
        if repository.nil?
          GitHub.logger.info(
            "Alert payload skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.repo.id": id,
            "gh.security_center.job.reason": "Repository not found.",
          )
          GitHub.dogstats.increment(
            "security_center.insights_entity_batch.alert_skipped",
            tags: all_stats_tags + ["reason:repo_not_found"]
          )
          next
        end

        out << repository if should_process_repository?(repository)
      end
      out
    end

    sig { returns(T::Array[String]) }
    memoize def repository_ids
      ids = entities_updated.map { |entity| entity["repository_id"] }
      ids += entities_deleted.map { |entity| entity["repository_id"] }
      ids.uniq.compact
    end

    sig { returns(T::Hash[String, ::Repository]) }
    memoize def repositories_lookup
      T.let(repository_ids.in_groups_of(BATCH_SIZE, false).flat_map do |batch_ids|
        ::Repository.active.where(id: batch_ids).map do |repo|
          [repo.id.to_s, repo]
        end
      end.to_h, T::Hash[String, ::Repository])
    end

    sig { returns(T::Hash[Integer, T::Boolean]) }
    memoize def repository_owner_in_scope_status
      repository_owner_status = T.let({}, T::Hash[Integer, T::Boolean])
      repositories_lookup.values.in_groups_of(BATCH_SIZE, false).flat_map do |repos|
        owner_ids = repos.map(&:owner_id).uniq.compact
        owners = ::User.where(id: owner_ids)
        owners.each do |owner|
          next unless owner.organization? || owner.user?

          if owner.user?
            next unless ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(owner)
          end

          repository_owner_status[owner.id] = SecurityFeatures.visible_features(owner).include?(feature_type)
        end
      end

      repository_owner_status
    end

    sig { params(repository: ::Repository).returns(T::Boolean) }
    def should_process_repository?(repository)
      owner_id = repository.owner_id
      owner_in_scope = repository_owner_in_scope_status[owner_id]

      if owner_in_scope.nil?
        GitHub.logger.info(
          "Alert payload skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository.id,
          "gh.repo.owner.id": owner_id,
          "gh.security_center.job.reason": "Repository not owned by org.",
        )
        GitHub.dogstats.increment(
          "security_center.insights_entity_batch.alert_skipped",
          tags: all_stats_tags + ["reason:owner_not_eligible"]
        )
        return false
      elsif !owner_in_scope
        GitHub.logger.info(
          "Alert payload skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository.id,
          "gh.repo.owner.id": owner_id,
          "gh.security_center.job.reason": "Repository owner not in scope.",
        )
        GitHub.dogstats.increment(
          "security_center.insights_entity_batch.alert_skipped",
          tags: all_stats_tags + ["reason:owner_not_in_scope"]
        )
        return false
      end

      true
    end
  end
end
