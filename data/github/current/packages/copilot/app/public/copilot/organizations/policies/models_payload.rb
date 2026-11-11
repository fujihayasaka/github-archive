# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class ModelsPayload < ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper

        sig { params(organization: ::Copilot::Organization).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { override.returns(String) }
        def route_id
          "copilotForBusinessModelsRoute"
        end

        sig { override.returns(T::Hash[String, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def payload
          call.transform_keys(&:to_s)
        end

        sig { returns(T.any(Copilot::Types::ModelPoliciesPayloadNew, Copilot::Types::ModelPoliciesPayload)) }
        def call
          copilot_business = @organization.copilot_business

          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          if copilot_business
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
          end

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            models: models_hash({
              # overrides for per-model description/helptext go here, keyed on the symbol of the config name
              ofct: {
                helptext: "Learn how GitHub Copilot serves #{Copilot::Policies::Models::Ofct.display_name} and confirm compatibility with your team's IDEs in our documentation."
              },
              grok_code: {
                description: "If enabled, members of this organization can access and send data to #{Copilot::Policies::Models::GrokCode.display_name}.",
                helptext: "Learn more."
              },
              sunflower: {
                description: if @organization.feature_flag_enabled?(:sunflower_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Sunflower.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Sunflower.display_name} when it becomes available."
                             end
              },
              m_spiderman: {
                description: if @organization.feature_flag_enabled?(:m_spiderman_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::MSpiderman.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::MSpiderman.display_name} when it becomes available."
                             end
              },
              m_thor: {
                description: if @organization.feature_flag_enabled?(:m_thor_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::MThor.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::MThor.display_name} when it becomes available."
                             end
              },
              tulip: {
                description: if @organization.feature_flag_enabled?(:tulip_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Tulip.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Tulip.display_name} when it becomes available."
                             end
              },
              lotus: {
                description: if @organization.feature_flag_enabled?(:lotus_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Lotus.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Lotus.display_name} when it becomes available."
                             end
              },
              arcticfox: {
                description: if @organization.feature_flag_enabled?(:arcticfox_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Arcticfox.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Arcticfox.display_name} when it becomes available."
                             end
              },
              watermelon: {
                description: if @organization.feature_flag_enabled?(:watermelon_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Watermelon.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Watermelon.display_name} when it becomes available."
                             end
              },
              cucumber: {
                description: if @organization.feature_flag_enabled?(:cucumber_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Cucumber.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Cucumber.display_name} when it becomes available."
                             end
              },
              blueberry: {
                description: if @organization.feature_flag_enabled?(:blueberry_roll_out_complete, default: false)
                               "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Blueberry.display_name} model."
                             else
                               "If enabled, members of this organization can access #{Copilot::Policies::Models::Blueberry.display_name} when it becomes available."
                             end
              },
            }),
            model_policies: model_policies_payload,
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            },
          }
        end

        private

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: T.nilable(String), description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(T.nilable(Copilot::Types::PoliciesIndexPayloadNewAspect)) }
        def build_policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
          return nil unless policy_class.available_for?(@organization)

          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by_org?(@organization),
            helptext: helptext,
            description: description,
            displayname: "#{policy_class.display_name} in Copilot",
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(policy_class.value(@organization), menu_items),
            preview: policy_class.preview?(@organization),
          }
        end

        sig { params(overrides: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, Copilot::Types::PoliciesIndexPayloadNewAspect]) } # rubocop:disable Sorbet/ForbidTUntyped
        def models_hash(overrides = {})
          res = {}
          Copilot::Policies::MODELS.each do |policy_class|
            next unless policy_class.viewable_by_org?(@organization)

            res[policy_class.config_name.to_sym] = {
              manages: policy_class.config_name,
              visible: true, # we only pass down visible models
              configurable: policy_class.editable_by?(@organization),
              helptext: "Learn more about how GitHub Copilot serves #{policy_class.display_name}.",
              description: "If enabled, members of this organization will have access to the latest #{policy_class.display_name} model.",
              displayname: "#{policy_class.display_name} in Copilot",
              helpurl: policy_class.documentation_url,
              options: make_general_menu_options(policy_class.value(@organization)),
              preview: policy_class.preview?(@organization),
            }
          end

          # Only apply overrides for keys that exist in the result hash
          overrides.each do |key, value|
            if res.key?(key)
              res[key] = res[key].deep_merge(value)
            end
          end

          res
        end

        sig { returns(T::Array[Copilot::Types::PoliciesIndexPayloadNewAspect]) }
        def model_policies_payload
          models = Copilot::ModelsRegistryCache.for_organization(@organization)
          model_policies = []
          models.each do |model|
            enablement_status = model_enablement_status(model.model_key)
            model_policies << {
              manages: model.model_key,
              visible: true, # visible is always true if copilot_model_registry_ui is enabled and the policy is included in the list
              configurable: !@organization.model_policy_inherited?(model.model_key),
              options: make_general_menu_options(enablement_status),
              helpurl: model.documentation_link,
              helptext:  model.documentation_link_text,
              displayname: model.name,
              description: model.description,
              preview: model.preview,
            } if @organization.feature_flag_enabled?(:copilot_model_registry_ui, default: false)
          end

          model_policies
        end

        sig { params(model_key: String).returns(String) }
        def model_enablement_status(model_key)
          return "disabled" if @organization.model_disabled?(model_key)
          return "enabled" if @organization.model_enabled?(model_key)

          "unconfigured"
        end

        sig do params(value: String, items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)])
          .returns(T::Array[Copilot::Types::MenuItemHashType])
        end
        def make_general_menu_options(value, items = Copilot::Policies::Menus::DEFAULT)
          items.map do |menu_item|
            menu_item.new(copilot_configurable: @organization, checked: value == menu_item.value).to_h
          end.compact
        end
      end
    end
  end
end
