# typed: false
# frozen_string_literal: true

require "github/current_tenant"

module ActiveJob
  module TenantContext
    extend ActiveSupport::Concern

    class InvalidTenantError < StandardError; end
    class TenantContextResolutionError < StandardError; end

    included do
      prepend ActiveJob::TenantContext::PrependMethods

      attr_accessor :current_tenant, :unscope_queries, :tenant_context_state_captured

      # This method is called before the job is enqueued, and if the job is running in a proxima environment (multi tenant enterprise),
      # we are setting the current tenant of the job object to the tenant that is running the job as well as the tenant scoping state.
      before_enqueue do |job|
        next unless GitHub.multi_tenant_enterprise?
        # defer to capture_tenant_context_for_propagation if enabled
        next if FeatureFlag.vexi.enabled?(:active_job_preserve_tenant_context_method, default: false)
        # don't set the current tenant if the job is being retried
        next if job.executions > 0

        job.current_tenant = current_tenant_excluding_stafftools
        job.unscope_queries = GitHub::CurrentTenant.unscoped? # can be nil, true or false
      end

      before_enqueue do
        next unless GitHub.multi_tenant_enterprise?
        next unless FeatureFlag.vexi.enabled?(:active_job_preserve_tenant_context_method, default: false)
        capture_tenant_context_for_propagation(at: :before_enqueue)
      end

      # This hook executes before the job is performed, and if the job is running in multi-tenant enterprise environment,
      # capture the tenant context for propagation if not already done so (i.e. when the job is executed with perform_now).
      before_perform do
        next unless GitHub.multi_tenant_enterprise?
        next unless FeatureFlag.vexi.enabled?(:active_job_preserve_tenant_context_method, default: false)
        capture_tenant_context_for_propagation(at: :before_perform)
      end

      # Because we are setting GitHub::CurrentTenant in deserialize (below), we shouldn't need to set it here, but if that context is lost,
      # we are ensuring the GitHub::CurrentTenant is set before the job is run, so that the job has access to it.
      around_perform do |_job, block|
        next block.call unless GitHub.multi_tenant_enterprise?

        set_current_tenant do
          set_query_scoping do
            block.call
          end
        end
      end

      before_perform :emit_tenant_context_metrics
    end

    module PrependMethods
      # If the job is running in a proxima environment (multi tenant enterprise), and the job object has a current_tenant attribute,
      # we serialize the ID and slug of the current tenant along with the scoping state.
      def serialize
        return super unless GitHub.multi_tenant_enterprise?

        hash = super

        if current_tenant.present?
          hash.merge!("X-GitHub-Tenant-ID" => current_tenant.id, "X-GitHub-Tenant" => current_tenant.slug)
        end

        hash.merge!("X-GitHub-Tenant-Scoped" => !unscope_queries)

        hash
      end

      # If the job is running in a proxima environment (multi tenant enterprise), we check the serialized job_data for the tenant identifier.
      # If found, we search for the Business corresponding to that slug or ID and set it as the current tenant so that the job has the GitHub::CurrentTenant set correctly.
      # If the
      def deserialize(job_data)
        return super unless GitHub.multi_tenant_enterprise?

        if job_data["X-GitHub-Tenant-ID"].present?
          @current_tenant = ActiveRecord::Base.connected_to(role: :reading) do
            Business.including_deleted.find(job_data["X-GitHub-Tenant-ID"])
          end
        elsif job_data["X-GitHub-Tenant"].present?
          @current_tenant = ActiveRecord::Base.connected_to(role: :reading) do
            Business.including_deleted.find_by_slug(job_data["X-GitHub-Tenant"])
          end
        end

        if job_data.key?("X-GitHub-Tenant-Scoped")
          @unscope_queries = !job_data["X-GitHub-Tenant-Scoped"]
        end

        # Prevent overwriting the current tenant since it was already set prior to deserialization; this prevents
        # clobbering previously captured state when requeueing the job after a failure (when retry_on is configured).
        @tenant_context_state_captured = true

        set_current_tenant do
          set_query_scoping do
            super
          end
        end
      end

      # Internal: Set the current tenant that was identified from the job payload.
      def set_current_tenant
        return yield unless current_tenant.present?
        GitHub::CurrentTenant.set(current_tenant)
        yield
      ensure
        GitHub::CurrentTenant.remove unless Rails.env.test?
      end

      # Internal: Ensure job execution properly scopes queries to the current tenant, or disables scoping when needed.
      #
      # Tenant scoping is enabled by default. For internal API requests, we need to disable tenant scoping when
      # tenant context is not provided and scoping the request to a specific tenant is not possible.
      #
      # Internal API requests are not required to provide a tenant context.
      def set_query_scoping
        return yield unless unscope_tenant_queries?

        GitHub::CurrentTenant.unscope do
          yield
        end
      end

      # Internal: Should this job perform with unscoped queries?
      #
      # Conditions under which we expect this:
      #   - Tenant context was not serialized for the job (the current tenant was set prior to queueing the job)
      #     - ...Or we expect a valid tenant to be resolved prior to the job by the tenant context resolver
      #   - The decision to unscope was serialized for the job (unscoping was set prior to queueing the job), or...
      #   - The job has been explicitly marked as exempt from the tenant context requirement and can therefore unscope
      #     - This implies that a tenant context resolver was not attached to the job
      def unscope_tenant_queries?
        return false if current_tenant.present? || self.class.job_resolves_tenant_context?

        unscope_queries || self.class.job_marked_for_unscoped_queries?
      end

      # Internal: Set the current tenant for the job.
      #    - If the current tenant is a stafftools tenant, it returns nil (ignoring the stafftools tenant).
      #    - If it is not a stafftools tenant, it returns the current tenant.
      def current_tenant_excluding_stafftools
        if GitHub::CurrentTenant.stafftools_tenant?
          nil
        else
          GitHub::CurrentTenant.get
        end
      end

      # Internal: Capture current tenant context to be propagated to the background worker.
      def capture_tenant_context_for_propagation(at:)
        return unless GitHub.multi_tenant_enterprise?
        return if tenant_context_state_captured

        self.current_tenant = current_tenant_excluding_stafftools
        self.unscope_queries = GitHub::CurrentTenant.unscoped? # can be nil, true or false
        self.tenant_context_state_captured = true

        tags = GitHub::CurrentTenant.metrics_tags + ["at:#{at}", "job:#{self.class.name.underscore}"]
        GitHub.dogstats.increment("tenant_context.background_jobs.context_captured", tags: tags)
      end

      def emit_tenant_context_metrics
        return unless GitHub.multi_tenant_enterprise?

        job_tags = [
          "job:#{self.class.name.underscore}",
          "tenant_context_requirement_temporarily_exempt:#{self.class.temporarily_exempt_from_tenant_context_requirement?}",
          "tenant_context_requirement_exempt:#{self.class.exempt_from_tenant_context_requirement?}",
          "resolve_tenant_context_defined:#{self.class.job_resolves_tenant_context?}"
        ]

        tags = GitHub::CurrentTenant.metrics_tags + job_tags

        GitHub.dogstats.increment("tenant_context.background_jobs", tags: tags)
      end
    end

    module ClassMethods
      def ensure_tenant_context_config_defined_once!(method)
        if !defined?(@tenant_context_configured)
          return @tenant_context_configured = method
        end

        raise TenantContextResolutionError, "Job defined #{@tenant_context_configured} configuration, but also tried to define #{method} configuration."
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

      # Class: Mark the job as exempt from the tenant context requirement in MT. This will result in the job running
      # with unscoped queries as long as a tenant has not been serialized for the job already. This should only be
      # called on jobs that do not need to operate on tenant data.
      def exempt_from_tenant_context_requirement
        ensure_tenant_context_config_defined_once!(__method__)
        @marked_as_exempt_from_tenant_context_requirement = true
      end

      # Class: Declare a way for the job to generate its own tenant context to operate within by providing a block
      # that resolves a tenant from the arguments passed to `perform`. This will result in the job scoping all queries
      # to the tenant returned from the provided block.
      def resolve_tenant_context(&block)
        ensure_tenant_context_config_defined_once!(__method__)

        raise TenantContextResolutionError, "Job #{self.class.name&.underscore} tried to define a tenant context resolver, but did not provide a block." unless block_given?

        @should_resolve_tenant_context = true

        before_perform do |job|
          next unless GitHub.multi_tenant_enterprise?

          resolved_tenant = GitHub::CurrentTenant.unscope { block.call(*job.arguments, job: job) }

          unless resolved_tenant.is_a?(Business)
            GitHub.logger.warn("Could not find a tenant to resolve for job", {
              "code.namespace": self.class.name&.underscore,
              "code.function": __method__,
            })
            next
          end

          current_tenant = GitHub::CurrentTenant.get

          if current_tenant != resolved_tenant
            GitHub.logger.warn("Current tenant does not match resolved tenant and will be overwritten", {
              "code.namespace": self.class.name&.underscore,
              "code.function": __method__,
              "github.current_tenant.slug": current_tenant&.slug,
              "github.resolved_tenant.slug": resolved_tenant&.slug,
            })
            GitHub::CurrentTenant.set(resolved_tenant)
          end
        end

        # defining emit_tenant_context_metrics callback again reorders the callback to run after resolve_tenant_context callback
        before_perform :emit_tenant_context_metrics
      end

      # Class / Internal: Will a tenant context resolver be run for this job?
      def job_resolves_tenant_context?
        return false unless GitHub.multi_tenant_enterprise?
        !!@should_resolve_tenant_context
      end

      # Class / Internal: Should the job unscope its queries?
      #
      # This should only be the case if the job is marked as exempt from the tenant context requirement, which implies
      # that no tenant context resolver has been attached to the job. This does not guarantee that the job will
      # unscope its queries, as the tenant context may have been serialized for the job; we respect the tenant context
      # provided to us from the initiator.
      def job_marked_for_unscoped_queries?
        return false unless GitHub.multi_tenant_enterprise?
        return true if temporarily_exempt_from_tenant_context_requirement?

        !!@marked_as_exempt_from_tenant_context_requirement
      end

      def temporarily_exempt_from_tenant_context_requirement?
        return false unless GitHub.multi_tenant_enterprise?
        !!@temporary_exemption_due_date && Date.today <= @temporary_exemption_due_date
      end

      def exempt_from_tenant_context_requirement?
        return false unless GitHub.multi_tenant_enterprise?
        !!@marked_as_exempt_from_tenant_context_requirement
      end
    end
  end
end
