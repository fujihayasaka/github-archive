# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class RepositoryDataCleanupJob < BatchedJob
    include GitHub::Memoizer

    queue_as :security_overview_analytics_repository_data_cleanup

    # We limit to have one retention job session at all time.
    locked_by timeout: 15.minutes, key: ->(job) do
      job.class.name
    end

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # Job needs to be able to process repositories across multiple tenants.
    exempt_from_tenant_context_requirement

    class TenantValidationResult < T::Struct
      # Workaround to avoid pull Organization/User model definitions in timed job script
      const :tenant, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
      const :is_in_scope, T::Boolean
      const :is_any_initialized, T::Boolean
    end

    sig do
      override.params(
        args: T.untyped,
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, offset_item_id:, **kwargs)
      ::SecurityOverviewAnalytics::Repository
        .where("repository_id > ?", offset_item_id)
        .order(:repository_id)
        .limit(BATCH_SIZE)
        .pluck(:repository_id)
    end

    sig do
      override.params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        offset_item_id: Integer,
        kwargs: T.untyped,
      ).void
    end
    def process_batch(repository_ids, *args, offset_item_id:, **kwargs)
      repo_ids_to_validate = T.let(repository_ids.deep_dup, T::Array[Integer])
      # To avoid a race condition with an ongoing onboarding, validate orphaned records with the revisions tables.
      repo_ids_to_validate += get_orphaned_revision_repository_ids(repository_ids, offset_item_id:)
      repo_ids_to_validate.uniq!

      repository_owner_ids = T.let({}, T::Hash[Integer, Integer])
      ::Repository.active.where(id: repo_ids_to_validate).in_batches(of: BATCH_SIZE) do |batch|
        repository_owner_ids.merge!(batch.pluck(:id, :owner_id).to_h)
      end

      owner_is_user_by_owner_id = T.let({}, T::Hash[Integer, T::Boolean])
      validation_result_by_owner_id = T.let({}, T::Hash[Integer, TenantValidationResult])
      ::User.where(id: repository_owner_ids.values.uniq).in_batches(of: BATCH_SIZE) do |batch|
        validation_result_by_owner_id.merge!(batch.map do |owner|

          owner_is_user_by_owner_id[owner.id] = owner.user?
          non_emu_user_out_of_scope = owner.user? && !(GitHub.single_business_environment? || owner.is_enterprise_managed?)

          if non_emu_user_out_of_scope
            [nil, nil]
          else
            [owner.id, TenantValidationResult.new(
              tenant: owner,
              is_in_scope: TenantValidationHelper.is_owner_in_scope?(owner),
              is_any_initialized: Initialization.for(owner).any_initialized?
            )]
          end
        end.to_h)
      end

      repositories_to_remove = T.let([], T::Array[Integer])
      owners_to_offboard = T.let([], T::Array[Integer])
      owners_to_initialize = T.let([], T::Array[T.any(::Organization, ::User)])

      repo_ids_to_validate.each do |repo_id|
        owner_id = repository_owner_ids[repo_id]

        unless owner_id.present?
          # If repository can't be located in Repositories.active, it's either marked as deleted or destroyed
          # We don't have owner_id to check the flag in that case
          # This code path existed before we added cleanup support for user-owned repos,
          # so it shouldn't regress
          instrument_repository_for_removal(:repo_not_found, repository_id: repo_id, owner_id:)
          repositories_to_remove << repo_id
          next
        end

        tenant_validation = validation_result_by_owner_id[owner_id]
        unless tenant_validation.present?
          instrument_repository_for_removal(:not_org_or_emu_owned_repo, repository_id: repo_id, owner_id:)
          repositories_to_remove << repo_id
          next
        end

        unless tenant_validation.is_in_scope
          instrument_repository_for_removal(:tenant_not_in_scope, repository_id: repo_id, owner_id:)
          owners_to_offboard << owner_id
          next
        end

        unless tenant_validation.is_any_initialized
          instrument_repository_for_initialization(:tenant_not_initialized, repository_id: repo_id, owner_id:)
          owners_to_initialize << tenant_validation.tenant
          next
        end
      end

      remove_repositories(repositories_to_remove) if repositories_to_remove.present?
      initialize_owners(owners_to_initialize) if owners_to_initialize.present?
      # TODO: https://github.com/github/security-center/issues/4161
      # offboard_owners(owners_to_offboard) if owners_to_offboard.present?
    end

    sig do
      override.params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        kwargs: T.untyped
      ).returns(T.nilable(Integer))
    end
    def next_batch_offset_item_id(repository_ids, *args, **kwargs)
      # Ids are sorted in ascending order thus last id is the largest
      repository_ids.last
    end

    sig { override.params(args: T.untyped, options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress)
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    private

    sig do
      params(
        repository_ids: T::Array[Integer],
        offset_item_id: Integer
      ).returns(T::Array[Integer])
    end
    def get_orphaned_revision_repository_ids(repository_ids, offset_item_id:)
      is_last_batch = !has_next_batch?(repository_ids)
      target_models = [FeatureStatusRevision, DependabotAlertRevision, CodeScanningAlertRevision, SecretScanningAlertRevision, CodeScanningPullRequestAlert]
      target_models.flat_map do |model|
        GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_data_cleanup.get_orphaned_revision_repository_ids.dist", tags: all_stats_tags + [
            "is_last_batch:#{is_last_batch}",
            "table:#{model.table_name}"
          ]
        ) do
          rel = model
            .where("repository_id > ?", offset_item_id)
            .select(:repository_id).distinct

          if repository_ids.any?
            rel = rel.where.not(repository_id: repository_ids)
            rel = rel.where("repository_id <= ?", T.must(repository_ids.max)) unless is_last_batch
          end

          T.let(rel.pluck(:repository_id), T::Array[Integer])
        end
      end
    end

    sig { params(repositories_to_remove: T::Array[Integer]).void }
    def remove_repositories(repositories_to_remove)
      # Since this is a low priority job, we don't need parallelism for data changes.
      # Thus we perform inline deletion instead of using a background job.
      target_models = [
        ::SecurityOverviewAnalytics::Repository,
        FeatureStatus,
        FeatureStatusRevision,
        DependabotAlertRevision,
        CodeScanningAlertRevision,
        SecretScanningAlertRevision,
        CodeScanningPullRequestAlert,
      ]
      target_models.each do |model|
        GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_data_cleanup.remove_repositories.dist", tags: all_stats_tags + [
            "table:#{model.table_name}"
          ]
        ) do
          model.delete_by_repository_ids(repositories_to_remove)
        end
      end
    end

    sig { params(reason: Symbol, repository_id: Integer, owner_id: T.nilable(Integer)).void }
    def instrument_repository_for_removal(reason, repository_id:, owner_id:)
      GitHub.logger.info(
        "Repository expected to be removed.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.owner.id": owner_id,
        "gh.security_overview_analytics.job.reason": reason
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.repository_data_cleanup.repository_to_remove",
        tags: all_stats_tags + ["reason:#{reason}"]
      )
    end

    sig { params(owners_to_initialize: T::Array[T.any(::Organization, ::User)]).void }
    def initialize_owners(owners_to_initialize)
      owners_to_initialize.uniq.each do |owner|
        next if owner.nil?
        if owner.user?
          Initialization::UserJob.perform_later(user_id: owner.id)
        else
          Initialization::OrganizationJob.perform_later(organization_id: owner.id)
        end
        FanoutScheduler.initialize_for(owner)
      end
    end

    sig { params(reason: Symbol, repository_id: Integer, owner_id: Integer).void }
    def instrument_repository_for_initialization(reason, repository_id:, owner_id:)
      GitHub.logger.info(
        "Repository's owner is expected to be initialized.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.owner.id": owner_id,
        "gh.security_overview_analytics.job.reason": reason
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.repository_data_cleanup.repository_to_initialize",
        tags: all_stats_tags + ["reason:#{reason}"]
      )
    end

    use_replicas \
      ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab
  end
end
