# typed: true
# frozen_string_literal: true

require "github/current_tenant"

module GitHub
  module StreamProcessors
    module TenantContext
      extend ActiveSupport::Concern
      extend T::Helpers

      include Kernel

      requires_ancestor { GitHub::StreamProcessors::BaseProcessor }

      class InvalidTenantError < StandardError; end
      class TenantContextResolutionError < StandardError; end

      included do
        T.bind(self, T.class_of(Hydro::Processor))

        if __callbacks[:message]
          set_callback :message, :around, :tenant_handling
          set_callback :message, :before, :emit_tenant_context_metrics
        end
      end

      def tenant_handling
        headers = Rack::Utils::HeaderHash.new(current_message.headers)
        if GitHub.multi_tenant_enterprise? && (id = headers["X-GitHub-Tenant-ID"])
          if ::FeatureFlag.vexi.enabled?(:tenant_handling_include_deleted, default: false)
            @current_tenant = with_read { Business.including_deleted.find(id) }
          else
            @current_tenant = with_read { Business.find(id) }
          end
          GitHub::CurrentTenant.set(@current_tenant)
        elsif GitHub.multi_tenant_enterprise? && (slug = headers["X-GitHub-Tenant"]) # if only slug is available, use that
          @current_tenant = with_read { Business.find_by(slug: slug) }
          GitHub::CurrentTenant.set(@current_tenant)
        elsif GitHub.multi_tenant_enterprise? && (slug = current_message.headers["tenant"]) # Remove after May 2023
          @current_tenant = with_read { Business.find_by(slug: slug) }
          GitHub::CurrentTenant.set(@current_tenant)
        else
          GitHub::CurrentTenant.remove
        end

        set_query_scoping do
          yield
        end
      ensure
        GitHub::CurrentTenant.remove
      end

      def emit_tenant_context_metrics
        return unless GitHub.multi_tenant_enterprise?

        processor_tags = [
          "processor:#{self.class.name&.underscore}",
          "service:#{logical_service}",
          "tenant_context_requirement_temporarily_exempt:#{self.class.temporarily_exempt_from_tenant_context_requirement?}",
          "tenant_context_requirement_exempt:#{self.class.exempt_from_tenant_context_requirement?}",
          "resolve_tenant_context_defined:#{self.class.stream_processor_resolves_tenant_context?}",
        ]
        tags = GitHub::CurrentTenant.metrics_tags + processor_tags
        GitHub.dogstats.increment("tenant_context.stream_processors", tags: tags)
      end

      def set_query_scoping
        return yield unless unscope_tenant_queries?

        GitHub::CurrentTenant.unscope do
          yield
        end
      end

      def unscope_tenant_queries?
        return false if @current_tenant.present? || self.class.stream_processor_resolves_tenant_context?

        self.class.stream_processor_marked_for_unscoped_queries?
      end

      module ClassMethods
        include Kernel
        include ActiveSupport::Callbacks::ClassMethods

        def ensure_tenant_context_config_defined_once!(method)
          if !defined?(@tenant_context_configured)
            return @tenant_context_configured = method
          end

          raise TenantContextResolutionError, "Stream processor defined #{@tenant_context_configured} configuration, but also tried to define #{method} configuration."
        end

        # Class: Mark the stream processor as exempt from the tenant context requirement in MT. This will result in
        # the stream processor running with unscoped queries as long as a tenant has not been serialized for the stream processor
        # already. This should only be called on stream processors that do not need to operate on tenant data.
        def exempt_from_tenant_context_requirement
          ensure_tenant_context_config_defined_once!(__method__)

          @marked_as_exempt_from_tenant_context_requirement = true
        end

        # Class: Mark the stream processor as temporarily exempt from the tenant context requirement in MT. This will result in the processor running
        # with unscoped queries as long as a tenant has not been serialized for the processor already. This is not a permanent exemption and processors will stop
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

        # Class: Declare a way for the stream processor to generate its own tenant context to operate within by providing a block
        # that resolves a tenant from the arguments passed to `perform`. This will result in the stream processor
        # scoping all queries to the tenant returned from the provided block.
        def resolve_tenant_context(&block)
          ensure_tenant_context_config_defined_once!(__method__)

          raise TenantContextResolutionError, "Stream processor #{self.class.name&.underscore} tried to define a tenant context resolver, but did not provide a block." unless block_given?

          @should_resolve_tenant_context = true

          set_callback :message, :before do |processor|
            T.bind(self, GitHub::StreamProcessors::BaseProcessor)
            next unless GitHub.multi_tenant_enterprise?

            resolved_tenant = GitHub::CurrentTenant.unscope { block.call(current_message, processor: processor) }

            unless resolved_tenant&.is_a?(Business)
              GitHub.logger.warn("Could not find a tenant to resolve for stream processor", {
                "code.namespace": self.class.name&.underscore,
                "code.function": __method__,
              })
              next
            end

            current_tenant = GitHub::CurrentTenant.get

            # if current_tenant is set, it means that the tenant context was provided to the stream processor via a header
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

          # defining emit_tenant_context_metrics callback again reorders the callback to run after resolve_tenant_context callback
          set_callback :message, :before, :emit_tenant_context_metrics
        end

        # Class / Internal: Will a tenant context resolver be run for this stream processor?
        def stream_processor_resolves_tenant_context?
          return false unless GitHub.multi_tenant_enterprise?
          !!@should_resolve_tenant_context
        end

        # Class / Internal: Should the stream processor unscope its queries?
        #
        # This should only be the case if the stream processor is marked as exempt from the tenant context requirement, which implies
        # that no tenant context resolver has been attached to the stream processor. This does not guarantee that the stream processor will
        # unscope its queries, as the tenant context may have been serialized for the stream processor; we respect the tenant context
        # provided to us from the initiator.
        def stream_processor_marked_for_unscoped_queries?
          return unless GitHub.multi_tenant_enterprise?
          return true if temporarily_exempt_from_tenant_context_requirement?

          !!@marked_as_exempt_from_tenant_context_requirement
        end

        def temporarily_exempt_from_tenant_context_requirement?
          return unless GitHub.multi_tenant_enterprise?
          !!@temporary_exemption_due_date && Date.today <= @temporary_exemption_due_date
        end

        def exempt_from_tenant_context_requirement?
          return unless GitHub.multi_tenant_enterprise?
          !!@marked_as_exempt_from_tenant_context_requirement
        end
      end
    end
  end
end
