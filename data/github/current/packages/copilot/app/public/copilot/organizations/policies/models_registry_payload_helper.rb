# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      module ModelsRegistryPayloadHelper
        include GitHub::Memoizer
        extend T::Helpers

        abstract!
        requires_ancestor { Copilot::Organizations::Policies::ModelsPayload }

        # Vendor display order for registry models
        # Lower numbers appear first, unrecognized vendors default to 999
        VENDOR_DISPLAY_ORDER = T.let({
          "Anthropic" => 1,
          "Google" => 2,
          "OpenAI" => 3,
          "Azure OpenAI" => 3,
          "xAI" => 4,
        }.freeze, T::Hash[String, Integer])

        private

        sig { params(overrides: T::Hash[Symbol, T.untyped]).returns(T::Array[Copilot::Types::PoliciesIndexPayloadNewAspect]) } # rubocop:disable Sorbet/ForbidTUntyped
        def model_policies_payload(overrides = {})
          # Build static models as sortable tuples: [vendor_order, name, index, data]
          # Index ensures uniqueness to prevent sort crashes on vendor+name collisions
          legacy_models = Copilot::Policies::MODELS.filter_map.with_index do |policy_class, index|
            next unless policy_class.viewable_by_org?(organization)

            model_data = {
              manages: policy_class.config_name,
              visible: true,
              configurable: policy_class.editable_by?(organization),
              helptext: "Learn more about how GitHub Copilot serves #{policy_class.display_name}.",
              description: "If enabled, members of this organization will have access to the latest #{policy_class.display_name} model.",
              displayname: "#{policy_class.display_name} in Copilot",
              helpurl: policy_class.documentation_url,
              options: make_general_menu_options(policy_class.value(organization)),
              preview: policy_class.preview?(organization),
            }

            # Apply overrides if they exist for this model
            config_key = policy_class.config_name.to_sym
            model_data = model_data.deep_merge(overrides[config_key]) if overrides.key?(config_key)

            # Return sortable tuple: [vendor_order, name, index, data]
            # Index ensures uniqueness even if vendor+name collide
            publisher = T.unsafe(policy_class).publisher&.serialize
            vendor_order = VENDOR_DISPLAY_ORDER[publisher || ""] || 999
            [vendor_order, policy_class.display_name, index, model_data]
          end

          # Build registry models as sortable tuples
          registry_models = []
          if organization.feature_flag_enabled?(:copilot_model_registry_ui, default: false)
            registry_models = Copilot::ModelsRegistryCache.for_organization(organization).map.with_index do |model, index|
              enablement_status = model_enablement_status(model.model_key)
              model_data = {
                manages: model.model_key,
                visible: true,
                configurable: !organization.model_policy_inherited?(model.model_key),
                options: make_general_menu_options(enablement_status),
                helpurl: model.documentation_link,
                helptext: model.documentation_link_text,
                displayname: model.name,
                description: model_description(model),
                preview: model.preview,
              }

              # Return sortable tuple: [vendor_order, name, index, data]
              # Index offset by 100000 to ensure registry models don't collide with static model indices
              vendor_order = VENDOR_DISPLAY_ORDER[model.vendor || ""] || 999
              [vendor_order, model.name, 100000 + index, model_data]
            end
          end

          # Merge, sort by tuple (vendor_order, name, index), and extract just the data
          (legacy_models + registry_models).sort.map(&:last)
        end

        sig { params(model_key: String).returns(String) }
        def model_enablement_status(model_key)
          return "disabled" if organization.model_disabled?(model_key)
          return "enabled" if organization.model_enabled?(model_key)

          "unconfigured"
        end

        sig { params(model: Copilot::ModelsRegistryCache).returns(String) }
        def model_description(model)
          if Copilot::ModelsRegistryCache.feature_flag_enabled?(model.policy_rollout_complete_feature_flag, organization)
            "If enabled, members of this organization will have access to the latest #{model.name} model."
          else
            "If enabled, members of this organization can access #{model.name} when it becomes available."
          end
        end
      end
    end
  end
end
