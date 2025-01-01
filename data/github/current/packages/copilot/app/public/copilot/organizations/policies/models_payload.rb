# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class ModelsPayload < ReactPayload::Base
        include GitHub::Memoizer
        include DocsUrlHelper

        sig { params(organization: ::Copilot::Organization, user: ::User).void }
        def initialize(organization:, user:)
          @organization = organization
          @user = user
          @use_refactor = T.let(@organization.feature_flag_enabled?(:copilot_org_settings_refactor, default: false), T::Boolean)
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
          copilot_business = @organization.copilot_business
          o1_policy_deprecated = @organization.feature_flag_enabled_or_raise?(:copilot_o1_policy_deprecated) ? true : false # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          can_edit_a_chat = true
          can_edit_a_f = true
          can_edit_afos = @organization.feature_flag_enabled_or_raise?(:copilot_afos) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_al = false
          can_edit_aofo = false
          can_edit_g_chat = true
          can_edit_g_tf = @organization.feature_flag_enabled_or_raise?(:copilot_g_tf) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_gtff = @organization.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_o1 = !o1_policy_deprecated
          can_edit_o3 = true
          can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_enterprise) : @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_business) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_o_fm = @organization.feature_flag_enabled_or_raise?(:copilot_o_fm) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_ofct = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled?(:copilot_ofct, default: false) : @organization.feature_flag_enabled?(:copilot_ofct_pro, default: false)
          can_edit_o_f = @organization.feature_flag_enabled_or_raise?(:copilot_o_f) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_o_t = @organization.feature_flag_enabled_or_raise?(:copilot_o_t) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_obmb = @organization.feature_flag_enabled_or_raise?(:copilot_obmb) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_obmw = @organization.feature_flag_enabled_or_raise?(:copilot_obmw) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_ofo = @organization.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_edit_grok_code = @organization.feature_flag_enabled?(:copilot_grok_code, default: false)

          can_see_copilot_chat_for_dotcom = true
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          can_see_a_chat = true
          can_see_a_f = true
          can_see_afos = @organization.feature_flag_enabled_or_raise?(:copilot_afos) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_al = @organization.copilot_plan_enterprise? && @organization.feature_flag_enabled_or_raise?(:copilot_al) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_aofo = @organization.copilot_plan_enterprise? && @organization.feature_flag_enabled_or_raise?(:copilot_aofo) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_g_chat = true
          can_see_g_tf = @organization.feature_flag_enabled_or_raise?(:copilot_g_tf) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_gtff = @organization.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_o1 = !o1_policy_deprecated
          can_see_o3 = true
          can_see_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_enterprise) : @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_business) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_o_fm = @organization.feature_flag_enabled_or_raise?(:copilot_o_fm) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_ofct = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled?(:copilot_ofct, default: false) : @organization.feature_flag_enabled?(:copilot_ofct_pro, default: false)
          can_see_o_f = @organization.feature_flag_enabled_or_raise?(:copilot_o_f) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_o_t = @organization.copilot_plan_enterprise? && @organization.feature_flag_enabled_or_raise?(:copilot_o_t) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_obmb = @organization.feature_flag_enabled_or_raise?(:copilot_obmb) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_obmw = @organization.feature_flag_enabled_or_raise?(:copilot_obmw) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_ofo = @organization.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          can_see_grok_code = @organization.feature_flag_enabled?(:copilot_grok_code, default: false)

          if copilot_business
            # if the business has an explicit policy, this user cannot edit it. So lets check for it.
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            can_edit_a_chat = copilot_business.a_chat_no_policy? || copilot_business.a_chat_unconfigured?
            can_edit_a_f = copilot_business.a_f_no_policy? || copilot_business.a_f_unconfigured?
            can_edit_afos = @organization.feature_flag_enabled_or_raise?(:copilot_afos) && (copilot_business.afos_no_policy? || copilot_business.afos_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_al = @organization.feature_flag_enabled_or_raise?(:copilot_al) && (copilot_business.al_no_policy? || copilot_business.al_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_aofo = @organization.feature_flag_enabled_or_raise?(:copilot_aofo) && (copilot_business.aofo_no_policy? || copilot_business.aofo_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_g_chat = copilot_business.g_chat_no_policy? || copilot_business.g_chat_unconfigured?
            can_edit_g_tf = @organization.feature_flag_enabled_or_raise?(:copilot_g_tf) && (copilot_business.g_tf_no_policy? || copilot_business.g_tf_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_gtff = @organization.feature_flag_enabled_or_raise?(:copilot_gtff) && (copilot_business.gtff_no_policy? || copilot_business.gtff_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_o1 = ((copilot_business.o1_no_policy? || copilot_business.o1_unconfigured?) && !o1_policy_deprecated) || false
            can_edit_o3 = copilot_business.o3_no_policy? || copilot_business.o3_unconfigured?
            can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_enterprise) : @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_business) && (copilot_business.o_ff_no_policy? || copilot_business.o_ff_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_o_fm = @organization.feature_flag_enabled_or_raise?(:copilot_o_fm) && (copilot_business.o_fm_no_policy? || copilot_business.o_fm_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_ofct = can_see_ofct && (copilot_business.ofct_no_policy? || copilot_business.ofct_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_o_f = copilot_business.o_f_no_policy? || copilot_business.o_f_unconfigured?
            can_edit_o_t = @organization.feature_flag_enabled_or_raise?(:copilot_o_t) && (copilot_business.o_t_no_policy? || copilot_business.o_t_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_ofo = @organization.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) && (copilot_business.ofo_no_policy? || copilot_business.ofo_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_enterprise) : @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_business) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_see_o_f = copilot_business.feature_flag_enabled_or_raise?(:copilot_o_f) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_obmb = @organization.feature_flag_enabled_or_raise?(:copilot_obmb) && (copilot_business.obmb_no_policy? || copilot_business.obmb_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_obmw = @organization.feature_flag_enabled_or_raise?(:copilot_obmw) && (copilot_business.obmw_no_policy? || copilot_business.obmw_unconfigured?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_grok_code = @organization.feature_flag_enabled?(:copilot_grok_code, default: false) && (copilot_business.grok_code_no_policy? || copilot_business.grok_code_unconfigured?)
          end

          if @organization.feature_flag_enabled_or_raise?(:copilot_o_ff_policy_deprecated) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            can_edit_o_ff = false
            can_see_o_ff = false
          end

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            a_chat: migratable_policy_hash({
              manages: "copilot_a_chat",
              configurable: can_edit_a_chat,
              visible: can_see_a_chat,
              helpurl: Copilot::COPILOT_A_CHAT_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_A_CHAT}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_A_CHAT} model.",
              displayname: "#{Copilot::COPILOT_A_CHAT} in Copilot",
              options: make_general_menu_options(@organization.a_chat),
              preview: !@organization.feature_flag_enabled_or_raise?(:a_chat_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::AChat),
            # note the unconfigured item is added client-side
            a_f: migratable_policy_hash({
              manages: "copilot_a_f",
              configurable: can_edit_a_f,
              visible: can_see_a_f,
              helpurl: Copilot::COPILOT_A_CHAT_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_A_F}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_A_F} model.",
              displayname: "#{Copilot::COPILOT_A_F} in Copilot",
              options: make_general_menu_options(@organization.a_f),
              preview: !@organization.feature_flag_enabled_or_raise?(:af_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::Af),
            afos:  migratable_policy_hash({
              manages: "copilot_afos",
              configurable: can_edit_afos,
              visible: can_see_afos,
              helpurl: Copilot::COPILOT_AFOS_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_AFOS}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_AFOS} model.",
              displayname: "#{Copilot::COPILOT_AFOS} in Copilot",
              options: make_general_menu_options(@organization.afos),
              preview: false,
            }, policy_class: Copilot::Policies::Models::Afos),
            aofo:  migratable_policy_hash({
              manages: "copilot_aofo",
              configurable: can_edit_aofo,
              visible: can_see_aofo,
              helpurl: Copilot::COPILOT_AOFO_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_AOFO}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_AOFO} model.",
              displayname: "#{Copilot::COPILOT_AOFO} in Copilot",
              options: make_general_menu_options(@organization.aofo),
              preview: !@organization.feature_flag_enabled_or_raise?(:aofo_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::Aofo),
            al:  migratable_policy_hash({
              manages: "copilot_al",
              configurable: can_edit_al,
              visible: can_see_al,
              helpurl: Copilot::COPILOT_AL_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_AL}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_AL} model.",
              displayname: "#{Copilot::COPILOT_AL} in Copilot",
              options: make_general_menu_options(@organization.al),
              preview: false,
            }, policy_class: Copilot::Policies::Models::Al),
            g_chat: migratable_policy_hash({
              manages: "copilot_g_chat",
              configurable: can_edit_g_chat,
              visible: can_see_g_chat,
              helpurl: Copilot::COPILOT_G_CHAT_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_G_CHAT}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_G_CHAT} model.",
              displayname: "#{Copilot::COPILOT_G_CHAT} in Copilot",
              options: make_general_menu_options(@organization.g_chat),
              preview: !@organization.feature_flag_enabled_or_raise?(:g_chat_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::GChat),
            g_tf:  migratable_policy_hash({
              manages: "copilot_g_tf",
              configurable: T.cast(can_edit_g_tf, T::Boolean),
              visible: can_see_g_tf,
              helpurl: Copilot::COPILOT_G_TF_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_G_TF}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_G_TF} model.",
              displayname: "#{Copilot::COPILOT_G_TF} in Copilot",
              options: make_general_menu_options(@organization.g_tf),
              preview: !@organization.feature_flag_enabled?(:g_tf_ga, default: false),
            }, policy_class: Copilot::Policies::Models::Gtf),
            gtff:  migratable_policy_hash({
              manages: "copilot_gtff",
              configurable: can_edit_gtff,
              visible: can_see_gtff,
              helpurl: Copilot::COPILOT_GTFF_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_GTFF}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_GTFF} model.",
              displayname: "#{Copilot::COPILOT_GTFF} in Copilot",
              options: make_general_menu_options(@organization.gtff),
              preview: true,
            }, policy_class: Copilot::Policies::Models::Gtff),
            o1: migratable_policy_hash({
              manages: "copilot_o1",
              configurable: can_edit_o1,
              visible: can_see_o1,
              displayname: "#{Copilot::COPILOT_O1} in Copilot",
              helpurl: nil,
              helptext: nil,
              description: "If enabled, members of this organization will have access to the #{Copilot::COPILOT_O1}.",
              options: make_general_menu_options(@organization.o1),
              preview: true,
            }, policy_class: Copilot::Policies::Models::O1),
            o3: migratable_policy_hash({
              manages: "copilot_o3",
              configurable: can_edit_o3,
              visible: can_see_o3,
              displayname: "#{Copilot::COPILOT_O3} in Copilot",
              helpurl: nil,
              helptext: nil,
              description: "If enabled, members of this organization will have access to the #{Copilot::COPILOT_O3} model.",
              options: make_general_menu_options(@organization.o3),
              preview: !@organization.feature_flag_enabled_or_raise?(:o3_mini_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::O3),
            o_ff: migratable_policy_hash({
              manages: "copilot_o_ff",
              configurable: can_edit_o_ff,
              visible: can_see_o_ff,
              displayname: "#{Copilot::COPILOT_O_FF} in Copilot",
              description: "If enabled, members of this organization will have access to the #{Copilot::COPILOT_O_FF} model in Copilot Chat.",
              helptext: nil,
              helpurl: nil,
              options: make_general_menu_options(@organization.o_ff),
              preview: true,
            }, policy_class: Copilot::Policies::Models::Off),
            o_fm:  migratable_policy_hash({
              manages: "copilot_o_fm",
              configurable: can_edit_o_fm,
              visible: can_see_o_fm,
              helpurl: Copilot::COPILOT_O_FM_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_O_FM}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_O_FM} model.",
              displayname: "#{Copilot::COPILOT_O_FM} in Copilot",
              options: make_general_menu_options(@organization.o_fm),
              preview: true,
            }, policy_class: Copilot::Policies::Models::Ofm),
            ofct:  migratable_policy_hash({
              manages: "copilot_ofct",
              configurable: can_edit_ofct,
              visible: can_see_ofct,
              helpurl: Copilot::COPILOT_OFCT_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_OFCT}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_OFCT} model.",
              displayname: "#{Copilot::COPILOT_OFCT} in Copilot",
              options: make_general_menu_options(@organization.ofct),
              preview: @organization.feature_flag_enabled?(:copilot_ofct_ga, default: false) ? false : true,
            }, policy_class: Copilot::Policies::Models::Ofct, omit_from_payload: !@organization.feature_flag_enabled?(:copilot_ofct, default: false)),
            o_f: {
              manages: "copilot_o_f",
              configurable: can_edit_o_f,
              visible: can_see_o_f,
              displayname: "#{Copilot::COPILOT_O_F} in Copilot",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_O_F} model.",
              helptext: nil,
              helpurl: nil,
              options: make_general_menu_options(@organization.o_f),
              preview: true,
            },
            o_t:  migratable_policy_hash({
              manages: "copilot_o_t",
              configurable: can_edit_o_t,
              visible: can_see_o_t,
              helpurl: Copilot::COPILOT_O_T_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_O_T}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_O_T} model.",
              displayname: "#{Copilot::COPILOT_O_T} in Copilot",
              options: make_general_menu_options(@organization.o_t),
              preview: true,
            }, policy_class: Copilot::Policies::Models::Ot),
            obmb:  migratable_policy_hash({
              manages: "copilot_obmb",
              configurable: can_edit_obmb,
              visible: can_see_obmb,
              helpurl: Copilot::COPILOT_OBMB_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_OBMB}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_OBMB} model.",
              displayname: "#{Copilot::COPILOT_OBMB} in Copilot",
              options: make_general_menu_options(@organization.obmb),
              preview: !@organization.feature_flag_enabled_or_raise?(:obmb_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::Obmb),
            obmw:  migratable_policy_hash({
              manages: "copilot_obmw",
              configurable: can_edit_obmw,
              visible: can_see_obmw,
              helpurl: Copilot::COPILOT_OBMW_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_OBMW}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_OBMW} model.",
              displayname: "#{Copilot::COPILOT_OBMW} in Copilot",
              options: make_general_menu_options(@organization.obmw),
              preview: !@organization.feature_flag_enabled_or_raise?(:obmw_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::Obmw),
            ofo:  migratable_policy_hash({
              manages: "copilot_ofo",
              configurable: can_edit_ofo,
              visible: can_see_ofo,
              helpurl: Copilot::COPILOT_OFO_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_OFO}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_OFO} model.",
              displayname: "#{Copilot::COPILOT_OFO} in Copilot",
              options: make_general_menu_options(@organization.ofo),
              preview: false,
            }, policy_class: Copilot::Policies::Models::Ofo),
            grok_code:  migratable_policy_hash({
              manages: "copilot_grok_code",
              configurable: can_edit_grok_code,
              visible: can_see_grok_code,
              helpurl: Copilot::COPILOT_GROK_CODE_DOCS,
              helptext: "Learn more.",
              description: "If enabled, members of this organization can access and send data to #{Copilot::COPILOT_GROK_CODE}.",
              displayname: "#{Copilot::COPILOT_GROK_CODE} in Copilot",
              options: make_general_menu_options(@organization.grok_code),
              preview: !@organization.feature_flag_enabled_or_raise?(:grok_code_ga), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            }, policy_class: Copilot::Policies::Models::GrokCode),
            copilot_for_dotcom_visible: can_see_copilot_chat_for_dotcom,
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            },
          }

        end

        private

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy, helptext: String, description: String, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)]).returns(T.nilable(Copilot::Types::PoliciesIndexPayloadNewAspect)) }
        def build_policy_hash(policy_class, helptext:, description:, menu_items: Copilot::Policies::Menus::DEFAULT)
          return nil unless policy_class.available_for?(@organization)

          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            helptext: helptext,
            description: description,
            displayname: policy_class.display_name,
            helpurl: policy_class.documentation_url,
            options: make_general_menu_options(policy_class.value(@organization), menu_items),
            preview: policy_class.preview?(@organization),
          }
        end

        sig { params(control_hash: Copilot::Types::PoliciesIndexPayloadNewAspect, policy_class: Copilot::Types::OrgMutablePolicy, menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)], omit_from_payload: T::Boolean).returns(T.nilable(Copilot::Types::PoliciesIndexPayloadNewAspect)) }
        def migratable_policy_hash(control_hash, policy_class:, menu_items: Copilot::Policies::Menus::DEFAULT, omit_from_payload: false)
          return nil if omit_from_payload

          if @use_refactor
            return build_policy_hash(policy_class, helptext: control_hash[:helptext], description: control_hash[:description], menu_items:)
          end

          control_hash
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
