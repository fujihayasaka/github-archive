# typed: strict
# frozen_string_literal: true

# NOTE: This policy is only used at the business level
# This policy does not propagate to an org, and will never use
# effective_value.

# Also, this policy can only be enabled or disabled.

module Copilot
  module Policies
    class WorkspaceForEmu
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "workspace_for_emu"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Workspace"
        end

        # no docs
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          if entity.sorbet_class == ::Business
            biz = T.cast(entity, Copilot::Business)
            return biz.business_object.enterprise_managed? && !GitHub.multi_tenant_enterprise?
          end

          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        # this should not ever be called, we'll just return nil
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          nil
        end

        sig { override.returns(T::Boolean) }
        def skip_organization_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        private

        # Can only be enabled or disabled, if SOMEHOW we get something different,
        # just make it disabled
        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :WORKSPACE_FOR_EMU_ENABLED,
            disabled: :WORKSPACE_FOR_EMU_DISABLED,
            no_policy: :WORKSPACE_FOR_EMU_DISABLED,
            unconfigured: :WORKSPACE_FOR_EMU_DISABLED,
            unknown: :WORKSPACE_FOR_EMU_UNKNOWN
          }
        end
      end
    end
  end
end
