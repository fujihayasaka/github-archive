# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Aofo
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "aofo"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Opus 4.1"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-claude-opus"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Anthropic
          end

          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def viewable_by_business?(copilot_business)
            return false unless super(copilot_business)
            copilot_business.can_access_copilot_enterprise_models?
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Enterprise, min_cfi_plan: Copilot::Plans::CFI::ProPlus) do
              case entity.sorbet_class.to_s
              when "User"
                user = T.cast(entity, Copilot::User)
                user.has_pro_plus_access? || user.has_cfe_access? || user.has_max_access?
              when "Organization"
                org = T.cast(entity, Copilot::Organization)
                org.copilot_plan_enterprise?
              when "Business"
                # we will always allow businesses to have this available for speed. this is checked a lot
                # this is fine because we won't propagate to cfb orgs, and at the user level we return false
                # if no cfe access
                true
              else
                false
              end
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
          end

          # only allow editing for cfe businesses
          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def editable_by_business?(copilot_business)
            super && copilot_business.can_access_copilot_enterprise_models?
          end

          private

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
              enabled: :AOFO_ENABLED,
              disabled: :AOFO_DISABLED,
              no_policy: :AOFO_NO_POLICY,
              unconfigured: :AOFO_UNCONFIGURED,
              unknown: :AOFO_UNKNOWN
            }
          end

          sig do override.returns({
              enabled: Integer,
              disabled: Integer,
              no_policy: Integer,
              unconfigured: Integer,
              invalid: Integer
            })
          end
          def twirp_values
            {
              enabled: MonolithTwirp::Copilot::Users::V1::AOFO::AOFO_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::AOFO::AOFO_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::AOFO::AOFO_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::AOFO::AOFO_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::AOFO::AOFO_INVALID
            }
          end
        end
      end
    end
  end
end
