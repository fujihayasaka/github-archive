# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class MobileCopilotPaywallData
      class << self

        sig { returns(MobileCopilotPaywall) }
        def default
          MobileCopilotPaywall.new(
            paywall_products: paywall_products,
            disclaimers: disclaimers,
            all_features: all_features
          )
        end

        private

        sig { returns(T::Array[MobileCopilotPaywallProduct]) }
        def paywall_products
          [
            MobileCopilotPaywallProduct.new(
              title: "Free",
              subtitle: "A fast way to get started with GitHub Copilot.",
              features_header: "What's included:",
              copilot_license_type: "copilot_free",
              features: [
                MobileCopilotPaywallProductFeature.new(
                  title: "Access to agent mode, Claude 3.5 Sonnet, GPT-4o, and more"
                ),
                MobileCopilotPaywallProductFeature.new(
                  title: "2,000 completions per month"
                ),
                MobileCopilotPaywallProductFeature.new(
                  title: "50 chats or premium requests per month"
                )
              ]
            ),

            MobileCopilotPaywallProduct.new(
              title: "Pro",
              subtitle: nil,
              features_header: "Everything in Free and:",
              copilot_license_type: "copilot_individual",
              features: [
                MobileCopilotPaywallProductFeature.new(
                  title: "Access to code review, Claude 3.7 Sonnet, o1, and more"
                ),
                MobileCopilotPaywallProductFeature.new(
                  title: "Unlimited completions and chats with base model"
                ),
                MobileCopilotPaywallProductFeature.new(
                  title: "10× more premium requests than Free, with the option to buy more!"
                )
              ]
            ),

            MobileCopilotPaywallProduct.new(
              title: "Pro+",
              subtitle: nil,
              features_header: "Everything in Pro and:",
              copilot_license_type: "copilot_individual_pro_plus",
              features: [
                MobileCopilotPaywallProductFeature.new(
                  title: "Access to all models, including GPT-4.5"
                ),
                MobileCopilotPaywallProductFeature.new(
                  title: "30× more premium requests than Free, with the option to buy more!"
                )
              ]
            )
          ]
        end

        sig { returns(T::Array[String]) }
        def disclaimers
          [
            "Copilot on GitHub Mobile (or platform), only offers chat messages and interactions.",
            "Option to purchase additional premium requests not available to users that subscribe or have subscribed to Pro or Pro+ through GitHub Mobile (a platform)."
          ]
        end

        sig { returns(T::Array[MobileCopilotPaywallFeatureComparisonSection]) }
        def all_features
          [
            # CHAT — Interactions
            MobileCopilotPaywallFeatureComparisonSection.new(
              title: "Chat",
              features: [
                MobileCopilotFeatureComparisonSubsection.new(
                  title: "Interactions",
                  plan_rows: [
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_free",
                      plan_title: "Free",
                      icon: "check",
                      subtitle: "Up to 50 per month"
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual",
                      plan_title: "Pro",
                      icon: "unlimited",
                      subtitle: "Unlimited with base model"
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual_pro_plus",
                      plan_title: "Pro+",
                      icon: "unlimited",
                      subtitle: "Unlimited with base model"
                    )
                  ]
                ),

                # Inline chat availability
                MobileCopilotFeatureComparisonSubsection.new(
                  title: "Inline chat",
                  plan_rows: [
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_free",
                      plan_title: "Free",
                      icon: "check",
                      subtitle: ""
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual",
                      plan_title: "Pro",
                      icon: "check",
                      subtitle: ""
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual_pro_plus",
                      plan_title: "Pro+",
                      icon: "check",
                      subtitle: ""
                    )
                  ]
                ),

                # Slash commands
                MobileCopilotFeatureComparisonSubsection.new(
                  title: "Generate tests, code, and more with slash commands",
                  plan_rows: [
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_free",
                      plan_title: "Free",
                      icon: "check",
                      subtitle: ""
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual",
                      plan_title: "Pro",
                      icon: "check",
                      subtitle: ""
                    ),
                    MobileCopilotFeatureComparisonSubsectionItem.new(
                      copilot_license_type: "copilot_individual_pro_plus",
                      plan_title: "Pro+",
                      icon: "check",
                      subtitle: ""
                    )
                  ]
                ),

                # Models available in chat
                MobileCopilotPaywallChatModels.new(
                  title: "Available models in chat",
                  plans: [
                    MobileCopilotPaywallChatModelPlan.new(
                      copilot_license_type: "copilot_free",
                      title: "Free",
                      models: [
                        MobileCopilotPaywallChatModel.new(title: "Anthropic Claude 3.5 Sonnet"),
                        MobileCopilotPaywallChatModel.new(title: "Google Gemini 2.0 Flash"),
                        MobileCopilotPaywallChatModel.new(title: "OpenAI GPT-4o"),
                        MobileCopilotPaywallChatModel.new(title: "OpenAI o3 mini")
                      ]
                    ),
                    MobileCopilotPaywallChatModelPlan.new(
                      copilot_license_type: "copilot_individual",
                      title: "Pro · Every model in Free and:",
                      models: [
                        MobileCopilotPaywallChatModel.new(title: "Anthropic Claude 3.7 Sonnet"),
                        MobileCopilotPaywallChatModel.new(title: "Anthropic Claude 3.7 Sonnet: Thinking")
                      ]
                    ),
                    MobileCopilotPaywallChatModelPlan.new(
                      copilot_license_type: "copilot_individual_pro_plus",
                      title: "Pro+ · Every model in Pro and:",
                      models: [
                        MobileCopilotPaywallChatModel.new(title: "OpenAI GPT-4.5")
                      ]
                    )
                  ]
                )
              ]
            )
          ]
        end
      end
    end
  end
end
