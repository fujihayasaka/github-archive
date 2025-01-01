# typed: strict
# frozen_string_literal: true

# This is very likely fully unused.
# Every single config has this set to unconfigured, so should be able
# to remove it from here, twirp, and hydro
# https://data.githubapp.com/sql/3cf19306-c4f9-441f-a197-1c8ffb576d4c
# https://github.com/github/heart-services/issues/5586

module Copilot
  module Policies
    class PrivateDocs
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "private_docs"
        end

        sig { override.returns(String) }
        def display_name
          "Private docs"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/provide-context/create-knowledge-bases"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return value(user) if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          # if nil, then the inherited value is unconfigured
          inherited_policy || "unconfigured"
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.returns(T::Boolean) }
        def hide_from_audit_log?
          true
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :private_docs
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
            enabled: :PRIVATE_DOCS_ENABLED,
            disabled: :PRIVATE_DOCS_DISABLED,
            no_policy: :PRIVATE_DOCS_NO_POLICY,
            unconfigured: :PRIVATE_DOCS_UNCONFIGURED,
            unknown: :PRIVATE_DOCS_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_NO_POLICY,
            unconfigured: MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_INVALID
          }
        end
      end
    end
  end
end
