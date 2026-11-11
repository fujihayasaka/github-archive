# typed: strict
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    module Copilot
      class ModelsRegistryCache

        sig { params(diagnostic_io: T.any(StringIO, IO)).void }
        def self.seed(diagnostic_io: $stdout)
          return if ::Copilot::ModelsRegistryCache.exists?

          seed_models.each do |model_attributes|
            ::Copilot::ModelsRegistryCache.create!(model_attributes)
          rescue ActiveRecord::RecordInvalid => e
            diagnostic_io.puts "Skipping model #{model_attributes[:model_key]}: #{e.message}"
          end

          diagnostic_io.puts "Seeded #{::Copilot::ModelsRegistryCache.count} models to copilot model_registry_cache"
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def self.seed_models
          [
            {
              model_key: "goose-free",
              name: "🪿 FREE",
              description: "🪿 For everyone",
              plans: %w[free pro pro_plus business enterprise],
              feature_flag: "registry_dotcom_goose_free",
              internal: false,
              preview: false,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: true,
              vendor: "Azure OpenAI",
            },
            {
              model_key: "goose-pro-plus-business",
              name: "🪿 PRO PLUS, BUSINESS, ENTERPRISE",
              description: "🪿 For Pro Plus, Business, and Enterprise users",
              plans: %w[pro_plus business enterprise],
              feature_flag: "registry_dotcom_goose_pro_plus_business",
              internal: false,
              preview: true,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "OpenAI",
            },
            {
              model_key: "goose-pro",
              name: "🪿 PRO",
              description: "🪿 For Pro Plus, Business, and Enterprise users",
              plans: %w[pro pro_plus business enterprise],
              feature_flag: "registry_dotcom_goose_pro",
              internal: false,
              preview: false,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "Azure OpenAI",
            },
            {
              model_key: "goose-pro-plus",
              name: "🪿 PRO PLUS",
              description: "🪿 For Pro Plus, Business, and Enterprise users",
              plans: %w[pro_plus enterprise],
              feature_flag: "",
              internal: false,
              preview: false,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "Google",
            },
            {
              model_key: "goose-business-enterprise",
              name: "🪿 Business and Enterprise",
              description: "🪿 For Business and Enterprise users",
              plans: %w[business enterprise],
              feature_flag: "registry_dotcom_goose_business_enterprise",
              internal: false,
              preview: true,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "Anthropic",
            },
            {
              model_key: "goose-enterprise",
              name: "🪿 Enterprise",
              description: "🪿 For Enterprise users",
              plans: ["enterprise"],
              feature_flag: "registry_dotcom_goose_enterprise",
              internal: false,
              preview: false,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "GitHub",
            },
            {
              model_key: "goose-enterprise-internal",
              name: "🪿 Enterprise",
              description: "🪿 For Enterprise users",
              plans: ["enterprise"],
              feature_flag: "copilot_debug",
              internal: true,
              preview: false,
              documentation_link: "https://docs.github.com/copilot/getting-started-with-github-copilot/about-github-copilot#github-copilot-models",
              documentation_link_text: "Learn more about GitHub Copilot models",
              inline_approval_enabled: false,
              vendor: "xAI",
            },
          ]
        end
      end
    end
  end
end
