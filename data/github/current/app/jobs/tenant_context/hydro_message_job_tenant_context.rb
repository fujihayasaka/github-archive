# typed: true
# frozen_string_literal: true

require "github/current_tenant"

module TenantContext
  module HydroMessageJobTenantContext
    include GitHub::ServiceMapping
    extend ActiveSupport::Concern
    extend T::Helpers
    extend T::Sig
    include Kernel

    class InvalidTenantError < StandardError; end
    class TenantContextResolutionError < StandardError; end

    included do
      T.bind(self, T.class_of(HydroMessageJob))

      set_callback :perform, :around, :set_tenant_context
      set_callback :perform, :before, :emit_set_tenant_context_metrics
    end

    # This method currently handles tenant headers sent by callers.
    # Future plans involve moving away from this approach in favor of using a `set_tenant_context` resolver
    # to explicitly set the tenant context as needed. Currently, callers must set this
    # header to ensure proper scoping of queries.

    # The `resolve_tenant_context` method is designed to parse workload inputs
    # (specifically, the job's message) and construct a tenant context from it.
    # This approach simplifies the process for the caller, requiring them only
    # to pass the message without additional steps.

    # Long-term, the goal is to transition away from relying on this `set_tenant_context`
    # method and fully adopt `resolve_tenant_context` as a more straightforward approach for setting tenant contexts.
    def set_tenant_context
      return yield unless GitHub.multi_tenant_enterprise?

      T.bind(self, HydroMessageJob)
      headers = Rack::Utils::HeaderHash.new(self.headers || {})

      if (id = headers["X-GitHub-Tenant-ID"])
        if GitHub.flipper[:hydro_message_job_use_find_by].enabled?
          business = with_read { Business.find_by(id:) }
        else
          business = with_read { Business.find(id) }
        end
        GitHub::CurrentTenant.set(business)
      elsif (slug = headers["X-GitHub-Tenant"]) # use slug if id isn't present
        business = with_read { Business.find_by(slug: slug) }
        GitHub::CurrentTenant.set(business)
      elsif (slug = headers["tenant"]) # "legacy", remove after May 2023
        business = with_read { Business.find_by(slug: slug) }
        GitHub::CurrentTenant.set(business)
      else
        GitHub::CurrentTenant.remove
      end

      set_query_scoping do
        yield
      end
    ensure
      GitHub::CurrentTenant.remove
    end

    def with_read(&block)
      ActiveRecord::Base.connected_to(role: :reading, &block)
    end

    def emit_set_tenant_context_metrics
      return unless GitHub.multi_tenant_enterprise?

      job_tags = [
        "job:#{self.class.name&.underscore}",
        "service:#{logical_service}",
        "tenant_context_requirement_temporarily_exempt:#{self.class.temporarily_exempt_from_tenant_context_requirement?}",
        "tenant_context_requirement_exempt:#{self.class.exempt_from_tenant_context_requirement?}",
        "resolve_tenant_context_defined:#{self.class.resolves_tenant_context?}",
      ]

      tags = GitHub::CurrentTenant.metrics_tags + job_tags
      GitHub.dogstats.increment("tenant_context.hydro_message_job", tags: tags)
    end

    def set_query_scoping
      return yield unless unscope_tenant_queries?

      GitHub::CurrentTenant.unscope do
        yield
      end
    end

    def unscope_tenant_queries?
      return false if @current_tenant.present? || self.class.hydro_message_job_resolves_tenant_context?

      self.class.hydro_message_job_marked_for_unscoped_queries?
    end

    module ClassMethods
      extend T::Sig
      include Kernel
      include ActiveSupport::Callbacks::ClassMethods

      def ensure_tenant_context_config_defined_once!(method)
        if !defined?(@tenant_context_configured)
          return @tenant_context_configured = method
        end

        raise TenantContextResolutionError, "Job defined #{@tenant_context_configured} configuration, but also tried to define #{method} configuration."
      end

      # Class: Mark the job as exempt from the tenant context requirement in MT. This will result in
      # the job running with unscoped queries as long as a tenant has not been serialized for the job
      # already. This should only be called on jobs that do not need to operate on tenant data.
      def exempt_from_tenant_context_requirement
        ensure_tenant_context_config_defined_once!(__method__)

        @marked_as_exempt_from_tenant_context_requirement = true
      end

      # Class: Mark the job as temporarily exempt from the tenant context requirement in MT. This will result in the job running
      # with unscoped queries as long as a tenant has not been serialized for the job already. This is not a permanent exemption and jobs will stop
      # running with unscoped queries after the until_date has passed.
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

      # Class: Declare a way for the job to generate its own tenant context to operate within by providing a block
      # that resolves a tenant from the `message`` instance attribute. This will result in the job
      # scoping all queries to the tenant returned from the provided block.
      def resolve_tenant_context(&block)
        ensure_tenant_context_config_defined_once!(__method__)

        raise TenantContextResolutionError, "Job #{self.class.name&.underscore} tried to define a tenant context resolver, but did not provide a block." unless block_given?

        @should_resolve_tenant_context = true

        set_callback :perform, :before do |job|
          next unless GitHub.multi_tenant_enterprise?
          message = job.message
          resolved_tenant = GitHub::CurrentTenant.unscope { block.call(message, job) }

          unless resolved_tenant.is_a?(Business)
            GitHub.logger.warn("Could not find a tenant to resolve for hydro message job", {
              "code.namespace": self.class.name&.underscore,
              "code.function": __method__,
            })
            next
          end

          current_tenant = GitHub::CurrentTenant.get

          # if current_tenant is set, it means that the tenant context was provided to the job via a header
          if current_tenant != resolved_tenant
            GitHub.logger.warn("Current tenant does not match resolved tenant and will be overwritten", {
              "code.namespace": self.class.name&.underscore,
              "code.function": __method__,
              "github.current_tenant.slug": current_tenant&.slug,
              "github.resolved_tenant.slug": resolved_tenant.slug,
              })
            GitHub::CurrentTenant.set(resolved_tenant)
          end
        end

        # defining emit_set_tenant_context_metrics callback again reorders the callback to run after resolve_tenant_context callback
        set_callback :perform, :before, :emit_set_tenant_context_metrics
      end

      # Class / Internal: Will a tenant context resolver be run for this job?
      def hydro_message_job_resolves_tenant_context?
        !!@should_resolve_tenant_context
      end

      # Class / Internal: Should the job unscope its queries?
      #
      # This should only be the case if the job is marked as exempt from the tenant context requirement, which implies
      # that no tenant context resolver has been attached to the job. This does not guarantee that the job will
      # unscope its queries, as the tenant context may have been serialized for the job; we respect the tenant context
      # provided to us from the initiator.
      def hydro_message_job_marked_for_unscoped_queries?
        return false unless GitHub.multi_tenant_enterprise?
        return true if temporarily_exempt_from_tenant_context_requirement?

        !!@marked_as_exempt_from_tenant_context_requirement
      end

      # Class / Internal: Will a tenant context resolver be run for this hydro message job?
      def resolves_tenant_context?
        return false unless GitHub.multi_tenant_enterprise?
        !!@should_resolve_tenant_context
      end

      def temporarily_exempt_from_tenant_context_requirement?
        return false unless GitHub.multi_tenant_enterprise?

        !!(@temporary_exemption_due_date && Date.today <= @temporary_exemption_due_date)
      end

      def exempt_from_tenant_context_requirement?
        return unless GitHub.multi_tenant_enterprise?
        !!@marked_as_exempt_from_tenant_context_requirement
      end
    end
  end
end
