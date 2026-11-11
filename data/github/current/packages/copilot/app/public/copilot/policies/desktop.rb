# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Desktop
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable
        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "desktop"
        end

        ### BEGIN UI
        sig { override.returns(String) }
        def display_name
          "Copilot in GitHub Desktop"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/using-copilot-in-github-desktop"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Organizations can use GitHub Copilot for assistance in GitHub Desktop."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization will get Copilot assistance in GitHub Desktop.",
            PolicyDescriptionChunk.new(text: "Learn more about Copilot in GitHub Desktop.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: "GitHub Copilot for assistance in GitHub Desktop", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end


        ### END UI

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotForBusinessMailer.desktop_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotForBusinessMailer.desktop_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
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
            enabled: :DESKTOP_ENABLED,
            disabled: :DESKTOP_DISABLED,
            no_policy: :DESKTOP_NO_POLICY,
            unconfigured: :DESKTOP_UNCONFIGURED,
            unknown: :DESKTOP_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_INVALID
          }
        end
      end
    end
  end
end
