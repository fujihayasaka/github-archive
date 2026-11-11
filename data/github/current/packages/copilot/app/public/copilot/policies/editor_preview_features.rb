# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class EditorPreviewFeatures
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
          "editor_preview_features"
        end

        sig { override.returns(String) }
        def display_name
          "Editor preview features"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#about-policies-for-github-copilot"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Organizations can have access to editor preview features."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["If enabled, members of this organization will have access to editor preview features, including MCP servers."]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use preview features in your editor.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url),
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          super && !copilot_user.has_limited_access?
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_next_edit_suggestions, default: false)
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
            enabled: :EDITOR_PREVIEW_FEATURES_ENABLED,
            disabled: :EDITOR_PREVIEW_FEATURES_DISABLED,
            no_policy: :EDITOR_PREVIEW_FEATURES_NO_POLICY,
            unconfigured: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
            unknown: :EDITOR_PREVIEW_FEATURES_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_INVALID
          }
        end
      end
    end
  end
end
