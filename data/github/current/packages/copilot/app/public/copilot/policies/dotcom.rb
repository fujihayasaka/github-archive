# typed: strict
# frozen_string_literal: true

# This is actually a grouping of policies: `github_enterprise_feature_group`, `dotcom_chat`, and `pr_summarizations`
#
# In the database, this policy is stored in `github_enterprise_feature_group`, and the other policies are
# updated after this policy is updated. We go through this system to ensure that we are properly propagating and running
# any other logic needed

module Copilot
  module Policies
    class Dotcom
      class << self # rubocop:disable Style/ClassMethodsDefinitions
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "github_enterprise_feature_group"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot in GitHub.com"
        end

        # there are a few docs urls, come back to this later perhaps
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          policy_features = [DotcomChat.display_name]
          unless CodeReview.viewable_by_business?(business)
            policy_features << PrSummarizations.display_name
            policy_features << CodeReview.display_name
          end
          policy_features << "knowledge base search"

          ["Organizations can use #{policy_features.to_sentence}."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          policy_features = T.let([PolicyDescriptionChunk.new(text: DotcomChat.display_name, href: DotcomChat.documentation_url)], T::Array[T.any(String, PolicyDescriptionChunk)])

          if org.copilot_plan_enterprise?
            policy_features << "and"
            policy_features << PolicyDescriptionChunk.new(text: "knowledge base search", href: "https://docs.github.com/copilot/github-copilot-enterprise/about-github-copilot-enterprise/knowledge-base-search-for-github-copilot-enterprise")
          end

          [
            "If enabled, members of this organization can use",
            *policy_features,
            "."
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          []
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # since this is a grouping of policies for cfb orgs and biz, we don't want it available for users
          return false if entity.sorbet_class == ::User

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # we won't ever directly read the value of this policy, instead opting to read values of the policies
        # it controls.
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          "disabled"
        end

        # dotcom chat and pr summaries should be updated after updates
        # dotcom beta features and user feedback should be updated conditionally
        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          Copilot::Policies::DotcomChat.update_business(copilot_business, value)
          Copilot::Policies::PrSummarizations.update_business(copilot_business, value)

          if value == "disabled" || value == "no_policy"
            Copilot::Policies::DotcomBetaFeatures.update_business(copilot_business, value)
            Copilot::Policies::UserFeedback.update_business(copilot_business, value)
          elsif value == "enabled"
            # when we re-enable the policy, reset beta features/feedback to default
            # this only has an actual effect when changing from no policy to enabled, and ensures
            # that the value will properly propagate to the org settings
            Copilot::Policies::DotcomBetaFeatures.update_business(copilot_business, "disabled")
            Copilot::Policies::UserFeedback.update_business(copilot_business, "enabled") # default for user feedback
          end
        end

        sig { override.params(copilot_org: Copilot::Organization, value: String).void }
        def post_organization_update(copilot_org, value)
          Copilot::Policies::DotcomChat.update_org(copilot_org, value)
          Copilot::Policies::PrSummarizations.update_org(copilot_org, value)

          if value == "disabled"
            Copilot::Policies::DotcomBetaFeatures.update_org(copilot_org, value)
            Copilot::Policies::UserFeedback.update_org(copilot_org, value)
          end
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end
      end
    end
  end
end
