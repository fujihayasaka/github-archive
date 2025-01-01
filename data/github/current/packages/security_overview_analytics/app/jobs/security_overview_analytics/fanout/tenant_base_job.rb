# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    class TenantBaseJob < BatchedJob
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer
      include FanoutThrottler
      include SessionHandler

      abstract!

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 15.minutes, key: ->(job) do
        tenant_scope = job.arguments.dig(0, :tenant_scope)
        tenant_id = job.arguments.dig(0, :tenant_id)
        owner_type = job.arguments.dig(0, :owner_type)
        action = job.arguments.dig(0, :action)
        DEFAULT_LOCK_STRINGIFY_PROC.call([tenant_scope, tenant_id, owner_type, action].compact)
      end

      resolve_tenant_context do |args|
        tenant_scope = Types::TenantScope.try_deserialize(args[:tenant_scope])
        return if tenant_scope.nil?

        tenant_id = args[:tenant_id]
        business_id = if tenant_scope == Types::TenantScope::Business
          tenant_id
        elsif tenant_scope == Types::TenantScope::Organization
          ::Organization.find_by(id: tenant_id)&.business_id
        elsif tenant_scope == Types::TenantScope::User
          ::User.find_by(id: tenant_id)&.business_id
        else
          T.absurd(tenant_scope)
        end
        ::Business.find_by(id: business_id)
      end

      around_enqueue do |job, block|
        if job.tenant_scope.nil? || job.allowed_tenant_scopes.exclude?(T.must(job.tenant_scope))
          raise ArgumentError.new("Invalid tenant_scope input.")
        end

        if job.tenant_id <= 0
          raise ArgumentError.new("Invalid tenant_id input.")
        end

        if job.tenant_scope == Types::TenantScope::Business && job.owner_type.nil?
          raise ArgumentError.new("Invalid owner_type input.")
        end

        if job.action.nil?
          raise ArgumentError.new("Invalid action input.")
        end

        if job.arguments.dig(0, :features).present? && job.features.any? { |feature| feature.nil? }
          raise ArgumentError.new("Invalid features input.")
        end

        block.call
      rescue ArgumentError
        job.clear_lock
        raise
      end

      around_perform do |_, block|
        next unless should_perform?
        next if is_first_batch? && sessions_locked?
        block.call
        GitHub.dogstats.increment("security_overview_analytics.tenant_fanout.processed", tags: all_stats_tags)
      end

      sig do
        override.params(
          ids: T::Array[Integer],
          args: T.untyped,
          kwargs: T.untyped,
        )
        .returns(T.nilable(Integer))
      end
      def next_batch_offset_item_id(ids, *args, **kwargs)
        ids.last
      end

      sig { override.params(ids: T::Array[Integer], args: T::Array[T.untyped], options: T.untyped).void }
      def finalize_batch(ids, *args, **options)
        is_last_batch = !has_next_batch?(ids, **options)
        try_lock_sessions(is_last_batch)

        # Because the hash lock is based on shared params between batches,
        # we need to release the hash lock before enqueuing the next batch.
        clear_lock
      end

      sig { override.returns(T::Array[T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob))]) }
      def fanout_jobs
        available_fanout_jobs
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        tags = super
        tags << "tenant_scope:#{tenant_scope&.serialize}"
        tags << "action:#{action&.serialize}"
        tags << "owner_type:#{owner_type&.serialize}" if owner_type.present?
        tags
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.tenant.scope": tenant_scope&.serialize,
          "gh.tenant.id": tenant_id,
          "gh.owner.type": owner_type&.serialize,
          "gh.security_overview_analytics.action": action&.serialize,
          "gh.security_overview_analytics.features": features.map { |i| i&.serialize }.inspect,
          "gh.security_overview_analytics.job.initial_start": initial_start&.iso8601(3),
          "gh.security_overview_analytics.job.offset_item_id": offset_item_id,
          "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress)
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      sig { returns(T.nilable(Types::TenantScope)) }
      memoize def tenant_scope
        Types::TenantScope.try_deserialize(arguments.dig(0, :tenant_scope))
      end

      sig { returns(Integer) }
      memoize def tenant_id
        arguments.dig(0, :tenant_id) || 0
      end

      sig { returns(T.nilable(Types::Owner)) }
      memoize def owner_type
        Types::Owner.try_deserialize(arguments.dig(0, :owner_type))
      end

      sig { returns(T.nilable(T.any(::Business, ::Organization, ::User))) }
      memoize def tenant
        scope = tenant_scope
        return unless scope.present?

        case scope
        when Types::TenantScope::Business
          ::Business.find_by(id: tenant_id)
        when Types::TenantScope::Organization
          ::Organization.find_by(id: tenant_id)
        when Types::TenantScope::User
          ::User.find_by(id: tenant_id)
        else
          T.absurd(scope)
        end
      end

      sig { returns(T.nilable(Types::Action)) }
      memoize def action
        Types::Action.try_deserialize(arguments.dig(0, :action))
      end

      sig { returns(T::Array[T.nilable(Types::Feature)]) }
      memoize def features
        features_arg = T.let(arguments.dig(0, :features), T.nilable(T::Array[String]))
        return Types::Feature.values if features_arg.blank?
        features_arg.map do |feature|
          Types::Feature.try_deserialize(feature)
        end
      end

      sig { returns(T.nilable(Time)) }
      memoize def initial_start
        arguments.dig(0, :initial_start)
      end

      sig { returns(Integer) }
      memoize def offset_item_id
        arguments.dig(0, :offset_item_id) || 0
      end

      sig { returns(T::Boolean) }
      memoize def is_first_batch?
        offset_item_id.zero?
      end

      sig { abstract.returns(T::Array[Types::TenantScope]) }
      def allowed_tenant_scopes; end

      sig { overridable.returns(T::Boolean) }
      def should_perform?
        if tenant.nil?
          log_fanout_stopped(:tenant_not_found)
          return false
        end

        true
      end

      sig { params(reason: Symbol).void }
      def log_fanout_stopped(reason)
        GitHub.logger.info(
          "Tenant fanout stopped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": reason,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.tenant_fanout.stopped",
          tags: all_stats_tags + ["reason:#{reason}"]
        )
      end
    end
  end
end
