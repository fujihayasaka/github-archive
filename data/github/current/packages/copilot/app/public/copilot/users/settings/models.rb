# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Settings
      module Models
        extend T::Helpers
        include Copilot::Users::Signatures
        include Copilot::Users::Settings::Policies
        include GitHub::Memoizer

        abstract!

        include HasConfiguration

        ######   BASIC MODELS   ######

        delegate :a_chat_no_policy?, :a_chat_unconfigured?,
                 :g_chat_no_policy?, :g_chat_unconfigured?,
                 :gtff_no_policy?,
                 :o3_no_policy?, :o3_unconfigured?,
                 :obmb_no_policy?,
                 :obmw_no_policy?,
                 :ofct_no_policy?,
                 :aofo_no_policy?,
                 :ofo_no_policy?,
                 :grok_code_no_policy?,
                 to: :configuration

        # a_chat methods
        sig { override.returns(String) }
        def a_chat
          if a_chat_enabled?
            "enabled"
          elsif a_chat_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.returns(T::Boolean) }
        def a_chat_configured?
          return true if copilot_organizations.any?(&:a_chat_configured?)

          ActiveRecord::Base.connected_to(role: :reading) do
            !configuration.a_chat_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def a_chat_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:a_chat_disabled?)
            return false if copilot_businesses.all?(&:a_chat_enabled?)
            return false if copilot_organizations.any?(&:a_chat_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:a_chat)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :a_chat)
            return configuration.a_chat_disabled? # you are a cfi user and you cannot disable chat
          end

          true
        end

        sig { override.void }
        def a_chat_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.a_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def a_chat_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:a_chat_disabled?)
            return true if copilot_businesses.all?(&:a_chat_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:a_chat_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:a_chat)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :a_chat)
            return configuration.a_chat_enabled? # you are a cfi user and you get CHAT
          end

          false
        end

        sig { override.void }
        def a_chat_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.a_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def a_chat_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_no_policy",
            tags: ["type:user"],
          )
        end

        # g_chat methods
        sig { override.returns(String) }
        def g_chat
          if g_chat_enabled?
            "enabled"
          elsif g_chat_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.returns(T::Boolean) }
        def g_chat_configured?
          return true if copilot_organizations.any?(&:g_chat_configured?)

          ActiveRecord::Base.connected_to(role: :reading) do
            !configuration.g_chat_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def g_chat_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:g_chat_disabled?)
            return false if copilot_businesses.all?(&:g_chat_enabled?)
            return false if copilot_organizations.any?(&:g_chat_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:g_chat)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :g_chat)
            return configuration.g_chat_disabled? # you are a cfi user and you cannot disable chat
          end

          true
        end

        sig { override.void }
        def g_chat_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.g_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def g_chat_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:g_chat_disabled?)
            return true if copilot_businesses.all?(&:g_chat_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:g_chat_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:g_chat)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :g_chat)
            return configuration.g_chat_enabled? # you are a cfi user and you get CHAT
          end

          false
        end

        sig { override.void }
        def g_chat_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.g_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def g_chat_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_no_policy",
            tags: ["type:user"],
          )
        end

        # gtff methods
        sig { returns(String) }
        def gtff
          if gtff_enabled?
            "enabled"
          elsif gtff_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def gtff_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.gtff_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.gtff_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def gtff_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:gtff_disabled?)
            return false if copilot_businesses.all?(&:gtff_enabled?)
            return false if copilot_organizations.any?(&:gtff_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:gtff)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :gtff)
            return configuration.gtff_disabled? # you are a cfi user and you cannot disable gtff
          end

          true
        end

        sig { override.void }
        def gtff_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.gtff_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.gtff_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def gtff_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:gtff_disabled?)
            return true if copilot_businesses.all?(&:gtff_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:gtff_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:gtff)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :gtff)
            return configuration.gtff_enabled? # you are a cfi user and you get gtff
          end

          false
        end

        sig { override.void }
        def gtff_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.gtff_no_policy",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def gtff_unconfigured?
          return false if copilot_organizations.any? { |org| !org.gtff_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.gtff_unconfigured?
          end
        end

        # o3 methods
        sig { override.returns(String) }
        def o3
          if o3_enabled?
            "enabled"
          elsif o3_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.returns(T::Boolean) }
        def o3_configured?
          return true if copilot_organizations.any?(&:o3_configured?)

          ActiveRecord::Base.connected_to(role: :reading) do
            !configuration.o3_unconfigured?
          end
        end

        sig { override.void }
        def o3_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.o3_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.o3_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def o3_disabled?
          return false if has_limited_access?

          if has_cfb_access?
            return true if copilot_businesses.any?(&:o3_disabled?)
            return false if copilot_businesses.all?(&:o3_enabled?)
            return false if copilot_organizations.any?(&:o3_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:o3)
            return true
          end

          if has_cfi_access?
            return false
          end

          configuration.o3_disabled? # you are a cfi user and you cannot disable chat
        end

        sig { override.void }
        def o3_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.o3_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.o3_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def o3_enabled?
          return true if has_limited_access?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:o3_disabled?)
            return true if copilot_businesses.all?(&:o3_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:o3_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:o3)
            return false
          end

          if has_cfi_access?
            return true
          end

          configuration.o3_enabled? # you are a cfi user and you get CHAT
        end

        sig { override.void }
        def o3_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.o3_no_policy",
            tags: ["type:user"],
          )
        end

        # obmb methods
        sig { override.returns(T::Boolean) }
        def obmb_unconfigured?
          return false if copilot_organizations.any? { |org| !org.obmb_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.obmb_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def obmb_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:obmb_disabled?)
            return true if copilot_businesses.all?(&:obmb_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:obmb_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:obmb)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :obmb)
            return configuration.obmb_enabled? # you are a cfi user and you get obmb
          end

          false
        end

        sig { override.returns(T::Boolean) }
        def obmb_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:obmb_disabled?)
            return false if copilot_businesses.all?(&:obmb_enabled?)
            return false if copilot_organizations.any?(&:obmb_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:obmb)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :obmb)
            return configuration.obmb_disabled? # you are a cfi user and you cannot disable obmb
          end

          true
        end

        sig { returns(String) }
        def obmb
          if obmb_enabled?
            "enabled"
          elsif obmb_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def obmb_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmb_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmb_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def obmb_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmb_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmb_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def obmb_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.obmb_no_policy",
            tags: ["type:user"],
          )
        end

        # obmw methods
        sig { override.returns(T::Boolean) }
        def obmw_unconfigured?
          return false if copilot_organizations.any? { |org| !org.obmw_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.obmw_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def obmw_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:obmw_disabled?)
            return true if copilot_businesses.all?(&:obmw_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:obmw_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:obmw)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :obmw)
            return configuration.obmw_enabled? # you are a cfi user and you get obmw
          end

          false
        end

        sig { override.returns(T::Boolean) }
        def obmw_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:obmw_disabled?)
            return false if copilot_businesses.all?(&:obmw_enabled?)
            return false if copilot_organizations.any?(&:obmw_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:obmw)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :obmw)
            return configuration.obmw_disabled? # you are a cfi user and you cannot disable obmw
          end

          true
        end

        sig { returns(String) }
        def obmw
          if obmw_enabled?
            "enabled"
          elsif obmw_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def obmw_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmw_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmw_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def obmw_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmw_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmw_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def obmw_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.obmw_no_policy",
            tags: ["type:user"],
          )
        end

        # ofct methods
        sig { override.returns(T::Boolean) }
        def ofct_unconfigured?
          return false if copilot_organizations.any? { |org| !org.ofct_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.ofct_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def ofct_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:ofct_disabled?)
            return true if copilot_businesses.all?(&:ofct_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:ofct_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofct)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofct)
            return configuration.ofct_enabled? # you are a cfi user and you get ofct
          end

          false
        end

        sig { override.returns(T::Boolean) }
        def ofct_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:ofct_disabled?)
            return false if copilot_businesses.all?(&:ofct_enabled?)
            return false if copilot_organizations.any?(&:ofct_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofct)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofct)
            return configuration.ofct_disabled? # you are a cfi user and you cannot disable ofct
          end

          true
        end

        sig { returns(String) }
        def ofct
          if ofct_enabled?
            "enabled"
          elsif ofct_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def ofct_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofct_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofct_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def ofct_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofct_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofct_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def ofct_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.ofct_no_policy",
            tags: ["type:user"],
          )
        end

        # aofo methods
        sig { override.returns(T::Boolean) }
        def aofo_unconfigured?
          return false if copilot_organizations.any? { |org| !org.aofo_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.aofo_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def aofo_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:aofo_disabled?)
            return true if copilot_businesses.all?(&:aofo_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:aofo_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:aofo)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :aofo)
            return configuration.aofo_enabled? # you are a cfi user and you get aofo
          end

          false
        end

        sig { override.returns(T::Boolean) }
        def aofo_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:aofo_disabled?)
            return false if copilot_businesses.all?(&:aofo_enabled?)
            return false if copilot_organizations.any?(&:aofo_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:aofo)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :aofo)
            return configuration.aofo_disabled? # you are a cfi user and you cannot disable aofo
          end

          true
        end

        sig { returns(String) }
        def aofo
          if aofo_enabled?
            "enabled"
          elsif aofo_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def aofo_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.aofo_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.aofo_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def aofo_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.aofo_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.aofo_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def aofo_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.aofo_no_policy",
            tags: ["type:user"],
          )
        end

        # ofo methods
        sig { returns(String) }
        def ofo
          if ofo_enabled?
            "enabled"
          elsif ofo_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def ofo_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofo_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofo_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def ofo_disabled?
          return false unless any_business_or_org_has_fsi_enabled?

          if has_cfb_access?
            return true if copilot_businesses.any?(&:ofo_disabled?)
            return false if copilot_businesses.all?(&:ofo_enabled?)
            return false if copilot_organizations.any?(&:ofo_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofo)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofo)
            if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              return false
            end

            if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              return false
            end

            return configuration.ofo_disabled? # you are a cfi user and you cannot disable chat
          end

          true
        end

        sig { override.void }
        def ofo_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofo_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofo_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def ofo_enabled?
          # Should always be enabled since this is the default model unless the user is part of an org or business that has the copilot_api_force_legacy_base_chat_model FF
          return true unless any_business_or_org_has_fsi_enabled?

          if has_cfb_access?
            return false if copilot_businesses.any?(&:ofo_disabled?)
            return true if copilot_businesses.all?(&:ofo_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:ofo_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofo)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofo)
            if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              return true
            end

            if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              return true
            end

            return configuration.ofo_enabled?
          end

          false
        end

        sig { override.void }
        def ofo_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.ofo_no_policy",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def ofo_unconfigured?
          return false if copilot_organizations.any? { |org| !org.ofo_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.ofo_unconfigured?
          end
        end

        # grok_code methods
        sig { override.returns(T::Boolean) }
        def grok_code_unconfigured?
          return false if copilot_organizations.any? { |org| !org.grok_code_unconfigured? }

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.grok_code_unconfigured?
          end
        end

        sig { override.returns(T::Boolean) }
        def grok_code_enabled?
          if has_cfb_access?
            return false if copilot_businesses.any?(&:grok_code_disabled?)
            return true if copilot_businesses.all?(&:grok_code_enabled?) unless copilot_businesses.empty?
            return true if copilot_organizations.any?(&:grok_code_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:grok_code)
            return false
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :grok_code)
            return configuration.grok_code_enabled? # you are a cfi user and you get grok_code
          end

          false
        end

        sig { override.returns(T::Boolean) }
        def grok_code_disabled?
          if has_cfb_access?
            return true if copilot_businesses.any?(&:grok_code_disabled?)
            return false if copilot_businesses.all?(&:grok_code_enabled?)
            return false if copilot_organizations.any?(&:grok_code_enabled?)
            return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:grok_code)
            return true
          end

          if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :grok_code)
            return configuration.grok_code_disabled? # you are a cfi user and you cannot disable grok_code
          end

          true
        end

        sig { override.returns(String) }
        def grok_code
          if grok_code_enabled?
            "enabled"
          elsif grok_code_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { override.void }
        def grok_code_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.grok_code_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def grok_code_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.grok_code_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.void }
        def grok_code_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_no_policy",
            tags: ["type:user"],
          )
        end


        sig { returns(T::Boolean) }
        memoize def any_business_or_org_has_fsi_enabled?
          business_enabled = copilot_businesses.any? { |business| business.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return true if business_enabled
          org_enabled = copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          org_enabled
        end

        ###### END BASIC MODELS ######
      end
    end
  end
end
