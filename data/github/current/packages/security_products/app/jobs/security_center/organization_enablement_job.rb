# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class OrganizationEnablementJob < BatchedJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :security_analysis_settings

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
      organization_id = job.arguments.dig(0, :organization_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([organization_id])
    end

    # Validate inputs before performing the job to catch missing data early.
    around_perform do |job, block|
      if job.organization.nil?
        GitHub.logger.info("No organization found.")
        next
      end

      if job.actor.nil?
        GitHub.logger.info("No actor found.")
        next
      end

      if job.user_session.nil?
        GitHub.logger.info("No user session found.")
        next
      end

      if job.arguments.dig(0, :update_types).empty?
        GitHub.logger.info("No update_types provided.")
        next
      end

      block.call
    end

    sig do
      params(
        args: T.untyped,
        organization_id: Integer,
        repositories_scope: T.any(T::Array[Integer], String),
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, organization_id:, repositories_scope:, offset_item_id:, **kwargs)
      repository_security_center_config_scope = ::SecurityCenter::Coverage::Enablement::MultiRepoEnablement.new(
        actor: T.must(actor),
        org: T.must(organization),
        repo_ids_or_query_string: repositories_scope,
        user_session: T.must(user_session)
      ).repository_security_center_config_scope

      repository_security_center_config_scope
        .where(RepositorySecurityCenterConfig.arel_table[:repository_id].gt(offset_item_id))
        .order(:repository_id)
        .limit(BATCH_SIZE)
        .pluck(:repository_id)
    end

    sig do
      params(
        batch: T::Array[Integer],
        args: T.untyped,
        kwargs: T.untyped,
      )
      .returns(T.nilable(Integer))
    end
    def next_batch_offset_item_id(batch, *args, **kwargs)
      batch.max
    end

    sig do
      params(
        batch: T::Array[Integer],
        args: T.untyped,
        actor_id: Integer,
        update_types: T::Array[Symbol],
        update_options: T::Hash[Symbol, T.untyped],
        kwargs: T.untyped,
      )
      .void
    end
    def process_batch(batch, *args, actor_id:, update_types:, update_options: {}, **kwargs)
      # Filtering batch through Repository.active here to make sure we're excluding any soft-deleted repos.
      Repository.active.where(id: batch).pluck(:id).each do |repository_id|
        RepositoryEnablementJob.perform_later(repository_id:, actor_id:, update_types:, update_options:)
        GitHub.dogstats.increment("security_center.enablement.fanout.count", tags: all_stats_tags)
      end
    end

    sig { params(args: T::Array[T.untyped], options: T.untyped).void }
    def finalize_batch(*args, **options)
      # Because the hash lock is only on the `organization_id` parameter, enqueues for subsequent batches would fail.
      # Release here before the next batch is enqueued.
      clear_lock
    end

    protected

    sig { returns(T::Array[String]) }
    def stats_tags
      tags = []

      arguments.dig(0, :update_types).each do |update_type|
        tags << "update_type:#{update_type}"
      end

      tags
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      update_options = arguments.dig(0, :update_options)
      update_options = nil if update_options.blank?

      super.merge({
        "gh.org.id": organization&.id,
        "gh.org.login": organization&.display_login,
        "gh.enduser.id": actor&.id,
        "gh.enduser.login": actor&.display_login,
        "gh.security_center.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_center.job.initial_start": arguments.dig(0, :initial_start),
        "gh.security_center.job.progress": arguments.dig(0, :progress),
        "gh.security_center.enablement.update_types": arguments.dig(0, :update_types)&.join(","),
        "gh.security_center.enablement.update_options": update_options&.map { |k, v| "#{k}:#{v}" }&.join(","),
        "gh.security_center.user_session_id": user_session&.id
      })
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      Organization.find_by(id: arguments.dig(0, :organization_id))
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      User.find_by(id: arguments.dig(0, :actor_id))
    end

    sig { returns(T.nilable(UserSession)) }
    memoize def user_session
      UserSession.find_by(id: arguments.dig(0, :user_session_id))
    end
  end
end
