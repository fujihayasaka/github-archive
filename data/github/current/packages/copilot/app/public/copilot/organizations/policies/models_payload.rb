# typed: strict
# frozen_string_literal: true

require "react_payload"

module Copilot
  module Organizations
    module Policies
      class ModelsPayload < ::ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper
        include Copilot::Organizations::Policies::ModelsRegistryPayloadHelper

        sig { returns(::Copilot::Organization) }
        attr_reader :organization

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

        sig { returns(Copilot::Types::ModelPoliciesPayload) }
        def call
          copilot_business = organization.copilot_business

          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          if copilot_business
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
          end

          {
            org_name: organization.__getobj__.display_login,
            copilot_plan: organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            model_policies: model_policies_payload(model_overrides),
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            },
            models_default_policy: models_default_policy,
          }
        end

        private

        sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def model_overrides
          {
            # overrides for per-model description/helptext go here, keyed on the symbol of the config name
            ofct: {
              helptext: "Learn how GitHub Copilot serves #{Copilot::Policies::Models::Ofct.display_name} and confirm compatibility with your team's IDEs in our documentation."
            },
            grok_code: {
              description: "If enabled, members of this organization can access and send data to #{Copilot::Policies::Models::GrokCode.display_name}.",
              helptext: "Learn more."
            },
            hulk: {
              description: if organization.feature_flag_enabled?(:copilot_hulk_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Hulk.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Hulk.display_name} when it becomes available."
                           end
            },
            blackpanther: {
              description: if organization.feature_flag_enabled?(:copilot_blackpanther_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Blackpanther.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Blackpanther.display_name} when it becomes available."
                           end
            },
            antman: {
              description: if organization.feature_flag_enabled?(:copilot_antman_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Antman.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Antman.display_name} when it becomes available."
                           end
            },
            captainamerica: {
              description: if organization.feature_flag_enabled?(:copilot_captainamerica_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Captainamerica.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Captainamerica.display_name} when it becomes available."
                           end
            },
            wintersoldier: {
              description: if organization.feature_flag_enabled?(:copilot_wintersoldier_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Wintersoldier.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Wintersoldier.display_name} when it becomes available."
                           end
            },
            cucumber: {
              description: if organization.feature_flag_enabled?(:cucumber_roll_out_complete, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::Cucumber.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::Cucumber.display_name} when it becomes available."
                           end
            },
            cherry: {
              description: if organization.feature_flag_enabled?(:cherry_roll_out_complete_no_registry, default: false)
                             "If enabled, members of this organization will have access to the latest #{Copilot::Policies::Models::CherryLegacy.display_name} model."
                           else
                             "If enabled, members of this organization can access #{Copilot::Policies::Models::CherryLegacy.display_name} when it becomes available."
                           end
            },
          }
        end

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: T.nilable(String), description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(T.nilable(Copilot::Types::PoliciesIndexPayloadNewAspect)) }
        def build_policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
          return nil unless policy_class.available_for?(organization)

          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(organization),
            configurable: policy_class.editable_by_org?(organization),
            helptext: helptext,
            description: description,
            displayname: "#{policy_class.display_name} in Copilot",
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(policy_class.value(organization), menu_items),
            preview: policy_class.preview?(organization),
            warning: nil,
          }
        end

        sig do params(value: String, items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)])
          .returns(T::Array[Copilot::Types::MenuItemHashType])
        end
        def make_general_menu_options(value, items = Copilot::Policies::Menus::DEFAULT)
          items.map do |menu_item|
            menu_item.new(copilot_configurable: organization, checked: value == menu_item.value).to_h
          end.compact
        end

        sig { returns(T.nilable(Copilot::Types::PoliciesIndexPayloadNewAspect)) }
        def models_default_policy
          policy_class = Copilot::Policies::ModelsDefault
          return nil unless policy_class.available_for?(organization)

          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(organization),
            configurable: policy_class.editable_by_org?(organization),
            helptext: "Learn more.",
            description: "Automatically applied to new models. Individual model availability can be configured separately.",
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(policy_class.value(organization), Copilot::Policies::Menus::DEFAULT),
            preview: policy_class.preview?(organization),
            warning: nil,
          }
        end
      end
    end
  end
end
