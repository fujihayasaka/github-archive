# typed: strict
# frozen_string_literal: true

# The Instrumentable concern is used to enable instrumentation for a given policy, both in Hydro and in the audit log.
# To enable instrumentation for your policy, you only need to extend this module and implement any missing methods.

module Copilot
  module Policies
    module Concerns
      module Instrumentable
        extend T::Helpers
        include Copilot::Policy

        abstract!

        # symbols used for instrumentation
        sig do abstract.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        private def instrumentation_symbols; end

        sig { overridable.returns(T::Boolean) }
        def skip_business_instrumentation?
          false
        end

        sig { overridable.returns(T::Boolean) }
        def skip_organization_instrumentation?
          false
        end

        sig { overridable.returns(T::Boolean) }
        def skip_user_instrumentation?
          false
        end

        sig { overridable.returns(T::Boolean) }
        def hide_from_audit_log?
          false
        end

        sig { overridable.returns(Symbol) }
        def instrumentation_key
          (config_name + "_setting").to_sym
        end

        # The value of the setting for instrumentation. This will use the value from the database
        # for orgs/businesses and the effective value for users. We pass in `all_policies`
        # to prevent user instrumentation from recomputing it a bunch
        sig { params(entity: Copilot::Types::CopilotEntity, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(Symbol)) }
        def instrumentation_value(entity, all_policies = nil)
          case entity.sorbet_class.to_s
          when "Business"
            return nil if skip_business_instrumentation?
          when "Organization"
            return nil if skip_organization_instrumentation?
          when "User"
            return nil if skip_user_instrumentation?
          end

          # we want to use the effective value for users so that our instrumentation is accurate to what
          # end users see
          policy_value = if entity.sorbet_class == ::User
            effective_value(T.cast(entity, Copilot::User), all_policies) || "disabled"
          else
            value(entity)
          end

          case policy_value
          when config_values[:enabled]
            instrumentation_symbols[:enabled]
          when config_values[:disabled]
            instrumentation_symbols[:disabled]
          when config_values[:no_policy]
            instrumentation_symbols[:no_policy]
          when config_values[:unconfigured]
            instrumentation_symbols[:unconfigured]
          else
            instrumentation_symbols[:unknown]
          end
        end
      end
    end
  end
end
