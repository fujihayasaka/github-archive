# typed: true
# frozen_string_literal: true

# Includes a series a helpers necessary to power the Conditional Access Policy framework (CAP) in the API
module Platform
  module Authorization
    module ConditionalAccessDependency
      include Kernel

      # To perform conditional access, we use the request's resource as input.
      # Traditionally what we did instead was to obtain the organization
      # parameter from access_allowed? options, but that is no longer sufficient
      # as there exist policies that apply to user-owned resources.
      #
      # This method obtains the resource from the access_allowed? options.
      # If no resource is provided, it will log and emit metrics to keep track of it,
      # and return ConditionalAccess::UnenforceableResource, which would effectively
      # cause a CAP bypass. We do that in order not to disrupt the operations of the API.
      # In test environment it will raise instead.
      def resource_for_conditional_access(action:, options:, fallback_takes_priority: false, tfca_method: :async_target_for_conditional_access)
        tags = ["origin:#{@origin}", "api_action:#{action}"]
        # making the fallback take priority prevents N+1s when calling resource.target_for_conditional_access
        # when the callsite has provided it via access_allowed? arguments
        #
        # this is a stopgap measure to reduce the impact of CAP Enforcement in the Public API
        # until a promise based implementation is introduced
        if fallback_takes_priority
          fallback = yield
          if fallback.present? && fallback != :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
            GitHub.dogstats.increment("cap.enforcer.api.rfca.count", tags: tags + ["source:fallback"])
            return fallback
          end
        end

        rfca = current_resource(options)
        tags += ["source:resource", "rfca_class:#{rfca&.class&.name}"]

        unless rfca.present?
          if raise_on_cap_inconsistency?
            inner_error = ::ConditionalAccess::Enforcer::NilResourceError.new("nil resource for conditional access will cause enforcement bypass - check arguments in access_allowed?(:#{action}, ...)")
            raise Platform::Errors::InternalExecution, inner_error
          end
          GitHub.logger.warn(
            "missing resource for conditional access for API action",
            {
              "rfca.class" => nil,
              "gh.api.action" => action,
              "gh.auth.origin" => @origin,
              "options" => options
            }
          )
          GitHub.dogstats.increment("cap.enforcer.api.rfca.count", tags: tags + ["error:missing"])

          fallback = yield
          return fallback if fallback.present? && fallback != :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

          # deliberately bypass conditional access to avoid causing exceptions in prod
          return ::ConditionalAccess::UnenforceableResource.instance
        end

        if !rfca.respond_to?(tfca_method)
          if raise_on_cap_inconsistency?
            inner_error = ::ConditionalAccess::Enforcer::NoTargetForConditionalAccessMethodError.new("#{rfca.class.name} does not implement #{tfca_method} method - cannot enforce policies")
            raise Platform::Errors::InternalExecution, inner_error
          end

          GitHub.logger.warn(
            "target type does not implement TFCA method",
            {
              "rfca.class" => rfca.class.name,
              "gh.api.action" => action,
              "gh.auth.origin" => @origin,
              "options" => options
            }
          )
          GitHub.dogstats.increment("cap.enforcer.api.rfca.count", tags: tags + ["error:method"])

          fallback = yield
          return fallback if fallback.present? && fallback != :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

          # deliberately bypass conditional access to avoid causing exceptions in prod
          return ::ConditionalAccess::UnenforceableResource.instance
        end

        GitHub.dogstats.increment("cap.enforcer.api.rfca.count", tags: tags)
        rfca
      end

      def current_resource(options)
        options[:resource]
      end

      def raise_on_cap_inconsistency?
        Rails.env.test?
      end
    end
  end
end
