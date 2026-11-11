# typed: true
# frozen_string_literal: true

module Platform
  class TenantTracker
    def self.emit_tenant_context_metrics(query, context)
      return unless GitHub.multi_tenant_enterprise?
      return if query.mutation?

      logs = GitHub::CurrentTenant.logging_context.merge(
        "info.message" => "GraphQL query tenant context metrics",
        "code.function" => "Platform::TenantTracker#emit_tenant_context_metrics",
        "gh.internal_api_host" => context[:internal_api_host],
        "graphql.operation.name" => context[:operation_name],
        "gh.request_id" => GitHub.context[:request_id],
        "http.user_agent" => GitHub.context[:user_agent],
        "gh.graphql.target" => context[:target],
        "gh.graphql.origin" => context[:origin],
        "gh.graphql.query_owning_catalog_service" => context[:query_owning_catalog_service],
        "gh.catalog_service" => GitHub.context[:catalog_service],
        "gh.graphql.scrubbed_query" => context[:scrubbed_query],
      )

      tags = GitHub::CurrentTenant.metrics_tags + [
        "internal_api_host:#{context[:internal_api_host]}",
      ]

      GitHub.dogstats.increment("tenant_context.graphql.queries", tags: tags)
      GitHub.logger.info(logs)
    end

    def initialize(context = {})
      @current_tenant = GitHub::CurrentTenant.get
      @context = context
    end

    def sync_log_query_tenant_context(object)
      return unless GitHub.multi_tenant_enterprise?
      return unless query?

      resolved_tenant = GitHub::CurrentTenant.unscope { resolve_tenant(object).sync }

      unless resolved_tenant
        GitHub.logger.warn(
          "info.message" => "GraphQL unable to resolve tenant for class",
          "gh.request_id" => GitHub.context[:request_id],
          "graphql.operation.name" => @context[:operation_name],
          "graphql.operation.id" => @context[:operation_id],
          "gh.object.class" => object.class.name,
          "gh.current_tenant.id" => @current_tenant&.id,
        )
        return
      end

      if @current_tenant.nil?
        @current_tenant = resolved_tenant
        GitHub.logger.info(
          "info.message" => "GraphQL query initial tenant resolved",
          "gh.request_id" => GitHub.context[:request_id],
          "graphql.operation.name" => @context[:operation_name],
          "graphql.operation.id" => @context[:operation_id],
          "gh.initial_resolved_tenant.id" => @current_tenant.id,
        )
        return
      end

      if @current_tenant != resolved_tenant
        GitHub.logger.warn(
          "info.message" => "GraphQL cross-tenant query detected",
          "gh.request_id" => GitHub.context[:request_id],
          "graphql.operation.name" => @context[:operation_name],
          "graphql.operation.id" => @context[:operation_id],
          "gh.current_tenant.id" => @current_tenant.id,
          "gh.resolved_tenant.id" => resolved_tenant.id,
        )
      else
        GitHub.logger.info(
          "info.message" => "GraphQL resolved the correct tenant",
          "gh.request_id" => GitHub.context[:request_id],
          "graphql.operation.name" => @context[:operation_name],
          "graphql.operation.id" => @context[:operation_id],
          "gh.current_tenant.id" => @current_tenant.id,
          "gh.resolved_tenant.id" => resolved_tenant.id,
        )
      end
    end

    private

    def resolve_tenant(object)
      case object
      when Repository
        object.async_enterprise_managed_business
      when Organization
        object.async_business
      when User
        object.async_enterprise_managed_business
      when Business
        Promise.resolve(object)
      else
        Promise.resolve(nil)
      end
    end

    def query?
      return true unless @context.respond_to?(:query)

      !@context.query.mutation?
    end
  end
end
