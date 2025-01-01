# typed: true
# frozen_string_literal: true

require "github/current_tenant"

module Platform
  module Helpers
    module TenantContext
      extend T::Helpers

      include Kernel

      extend ActiveSupport::Concern

      requires_ancestor { Platform::Mutations::Base }

      # Public: Set the tenant context for the mutation using one of three mutation configurations:
      #  - `resolve_tenant_context`
      #  - `exempt_from_tenant_context_requirement`
      #  - `temporarily_exempt_from_tenant_context_requirement`
      # Long-term, the goal is to transition away from relying on X-Tenant* headers for internal service calls and to
      # instead rely on `resolve_tenant_context` to set the tenant context.
      # Today, the X-Tenant* headers are pulled off of the request and used to scope / unscope tenant queries in
      # `lib/github/middleware/tenant_selection.rb`. In th absence of a tenant header, we can expect that the
      # middleware will have already unscoped queries, so we need to re-scope if a tenant is resolved in `set_tenant`.
      sig { params(args: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def set_graphql_tenant_context(args)
        return yield unless GitHub.multi_tenant_enterprise?

        initial_tenant = GitHub::CurrentTenant.get
        initial_scoping_unscoped = GitHub::CurrentTenant.unscoped?

        set_tenant(args) do
          log_graphql_context(initial_tenant, initial_scoping_unscoped)

          set_query_scoping do
            yield
          end
        end
      end

      private

      # Set the tenant using the tenant context resolver, if one has been defined.
      sig { params(args: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def set_tenant(args)
        return yield unless tenant_context_should_resolve?

        GitHub::CurrentTenant.restore_tenant_context do
          resolved_tenant = resolve_tenant(args)

          if resolved_tenant_is_invalid?(resolved_tenant)
            log_tenant_resolution_failure
            return yield
          end

          # We use T.must here to assert to Sorbet that resolved_tenant cannot be nil at this point.
          # T.must will raise an exception at runtime if resolved_tenant is nil, but this should never happen due to the control flow.
          if current_tenant_does_not_match?(T.must(resolved_tenant))
            log_tenant_mismatch(T.must(resolved_tenant))
            GitHub::CurrentTenant.set(T.must(resolved_tenant))
            GitHub::CurrentTenant.rescope
          end

          yield
        end
      end

      sig { returns(T::Boolean) }
      def tenant_context_should_resolve?
        self.class.mutation_resolves_tenant_context?
      end

      # This method can return any application record.
      sig { params(args: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def resolve_tenant(args)
        GitHub::CurrentTenant.unscope { self.class.tenant_context_resolver.call(**args) }
      end

      # This method can accept any application record as the resolved_tenant.
      sig { params(resolved_tenant: T.untyped).returns(T::Boolean) }
      def resolved_tenant_is_invalid?(resolved_tenant)
        !resolved_tenant.is_a?(Business)
      end

      sig { void }
      def log_tenant_resolution_failure
        GitHub.logger.warn("Could not find a tenant to resolve for mutation", {
          "code.namespace": self.class.name&.underscore,
          "code.function": __method__,
        })
      end

      sig { params(resolved_tenant: Business).returns(T::Boolean) }
      def current_tenant_does_not_match?(resolved_tenant)
        current_tenant = GitHub::CurrentTenant.get
        current_tenant != resolved_tenant
      end

      sig { params(resolved_tenant: Business).void }
      def log_tenant_mismatch(resolved_tenant)
        current_tenant = GitHub::CurrentTenant.get
        GitHub.logger.warn("Current tenant does not match resolved tenant and will be overwritten", {
          "code.namespace": self.class.name&.underscore,
          "code.function": __method__,
          "github.current_tenant.slug": current_tenant&.slug,
          "github.resolved_tenant.slug": resolved_tenant.slug,
        })
      end

      # Private: Unscope queries executed in the yielded block if unscope_queries? is true.
      def set_query_scoping
        return yield unless unscope_queries?

        GitHub::CurrentTenant.unscope do
          yield
        end
      end

      # Private: Should the mutation be run with unscoped queries?
      sig { returns(T.nilable(T::Boolean)) }
      def unscope_queries?
        return false if GitHub::CurrentTenant.get.present? # the tenant was previously set upstream, or by a resolver
        return true if self.class.mutation_marked_for_unscoped_queries? # the mutation was marked as exempt

        preserve_unscoped_query_context? # no config was defined on the mutation and it is already unscoped
      end

      # Private: In the case that a mutation does not have a tenant context configuration defined, we need to preserve
      # any unscoping that has been set. This is necessary to prevent mutations from failing when a tenant header has
      # not been sent, and the mutation needs tenant context, but the service owner hasn't yet defined a resolver.
      # In these cases, we want to preserve the unscoped query context so that the mutation can run.
      # If the mutation did have a tenant context resolver attached, but it could not find the tenant, we will have
      # logged to Splunk and will continue executing the mutation with query scoping *enabled*, like other workloads.
      sig { returns(T.nilable(T::Boolean)) }
      def preserve_unscoped_query_context?
        return false if self.class.tenant_context_config_defined?

        GitHub::CurrentTenant.unscoped?
      end

      def log_graphql_context(initial_tenant, initial_scoping_unscoped)
        initial_tenant_overwritten = if initial_tenant.present? && GitHub::CurrentTenant.get.present?
          initial_tenant != GitHub::CurrentTenant.get
        else
          "n/a"
        end

        tags = GitHub::CurrentTenant.metrics_tags + [
          "catalog_service:#{context[:current_catalog_service]}",
          "mutation:#{self.class.name&.underscore}",
          "initial_query_scoping:#{initial_scoping_unscoped ? "disabled" : "enabled"}",
          "initial_tenant_set:#{initial_tenant.present?}",
          "initial_tenant_overwritten:#{initial_tenant_overwritten}",
          "internal_api_host:#{context[:internal_api_host]}",
          "mutation_resolves_tenant_context:#{self.class.mutation_resolves_tenant_context?}",
          "mutation_marked_for_unscoped_queries:#{self.class.mutation_marked_for_unscoped_queries?}",
          "temporarily_exempt_from_tenant_context_requirement:#{!!self.class.temporarily_exempt_from_tenant_context_requirement?}",
        ]

        logging_context = GitHub::CurrentTenant.logging_context.merge(
          "code.namespace" => self.class.name&.underscore,
          "code.function" => __method__,
          "gh.catalog_service" => context[:current_catalog_service],
          "gh.initial_query_scoping" => initial_scoping_unscoped ? "disabled" : "enabled",
          "gh.initial_tenant_set" => initial_tenant.present?,
          "gh.initial_tenant.id" => initial_tenant&.id,
          "gh.iniital_tenant.slug" => initial_tenant&.slug,
          "gh.initial_tenant_overwritten" => initial_tenant_overwritten,
          "gh.internal_api_host" => context[:internal_api_host],
          "gh.mutation_resolves_tenant_context" => self.class.mutation_resolves_tenant_context?,
          "gh.mutation_marked_for_unscoped_queries" => self.class.mutation_marked_for_unscoped_queries?,
          "gh.temporarily_exempt_from_tenant_context_requirement" => !!self.class.temporarily_exempt_from_tenant_context_requirement?,
          "gh.request_id" => context[:request_id],
        )

        GitHub.dogstats.increment("tenant_context.graphql.mutations", tags: tags)
        GitHub.logger.info(logging_context)
      end

      module ClassMethods
        include Kernel

        sig { returns(T::Boolean) }
        def tenant_context_config_defined?
          mutation_resolves_tenant_context? || mutation_marked_for_unscoped_queries?
        end

        sig { params(method: T.nilable(Symbol)).returns(T.untyped) }
        def ensure_tenant_context_config_defined_once!(method)
          if !defined?(@tenant_context_configured)
            return @tenant_context_configured = method
          end

          raise Platform::Errors::TenantContextResolution, "Mutation defined #{@tenant_context_configured} configuration, but also tried to define #{method} configuration."
        end

        # Class: Mark the mutation as temporarily exempt from the tenant context requirement in MT. This will result in the mutation running
        # with unscoped queries as long as a tenant has not been serialized for the mutation already. This is not a permanent exemption and mutations will stop
        # running with unscoped queries after the until_date has passed.
        sig { params(until_date: T.untyped).returns(Date) }
        def temporarily_exempt_from_tenant_context_requirement(until_date:)
          ensure_tenant_context_config_defined_once!(__method__)
          @temporary_exemption_due_date =
            case until_date
            when Date
              until_date
            else
              Date.parse(until_date)
            end
        end

        # Class: Mark the mutation as exempt from the tenant context requirement in MT. This will result in the mutation running
        # with unscoped queries as long as a tenant has not been serialized for the mutation already. This should only be
        # called on mutations that do not need to operate on tenant data.
        sig { returns(TrueClass) }
        def exempt_from_tenant_context_requirement
          ensure_tenant_context_config_defined_once!(__method__)
          @marked_as_exempt_from_tenant_context_requirement = true
        end

        # Class: Declare a way for the mutation to generate its own tenant context to operate within by providing a block
        # that resolves a tenant from the arguments passed to `perform`. This will result in the mutation scoping all queries
        # to the tenant returned from the provided block.
        sig { params(block: T.nilable(Proc)).returns(Proc) }
        def resolve_tenant_context(&block)
          ensure_tenant_context_config_defined_once!(__method__)

          raise Platform::Errors::TenantContextResolution, "Mutation #{self.class.name&.underscore} tried to define a tenant context resolver, but did not provide a block." unless block_given?

          @should_resolve_tenant_context = true
          @tenant_context_resolver = block
        end

        sig { returns(Proc) }
        def tenant_context_resolver
          @tenant_context_resolver
        end

        # Class / Internal: Will a tenant context resolver be run for this mutation?
        sig { returns(T::Boolean) }
        def mutation_resolves_tenant_context?
          !!@should_resolve_tenant_context
        end

        # Class / Internal: Should the mutation unscope its queries?
        #
        # This should only be the case if the mutation is marked as exempt from the tenant context requirement, which implies
        # that no tenant context resolver has been attached to the mutation. This does not guarantee that the mutation will
        # unscope its queries, as the tenant context may have been serialized for the mutation; we respect the tenant context
        # provided to us from the initiator.
        sig { returns(T::Boolean) }
        def mutation_marked_for_unscoped_queries?
          return false unless GitHub.multi_tenant_enterprise?
          return true if temporarily_exempt_from_tenant_context_requirement?

          !!@marked_as_exempt_from_tenant_context_requirement
        end

        sig { returns(T::Boolean) }
        def temporarily_exempt_from_tenant_context_requirement?
          !!(@temporary_exemption_due_date && Date.today <= @temporary_exemption_due_date)
        end
      end
    end
  end
end
