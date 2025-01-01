# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      module Models
        extend T::Helpers
        include Copilot::Organizations::Signatures

        abstract!

        include HasConfiguration

        ######   BASIC MODELS   ######

        delegate :a_chat, :a_chat_unconfigured?, :a_chat_configured?, :a_chat_enabled?,
                 :a_chat_disabled?, :a_chat_no_policy?,
                 :g_chat, :g_chat_unconfigured?, :g_chat_configured?, :g_chat_enabled?,
                 :g_chat_disabled?, :g_chat_no_policy?,
                 :gtff, :gtff_unconfigured?, :gtff_enabled?,
                 :gtff_disabled?, :gtff_no_policy?,
                 :o3, :o3_unconfigured?, :o3_configured?, :o3_enabled?,
                 :o3_disabled?, :o3_no_policy?,
                 :ofct, :ofct_unconfigured?, :ofct_enabled?,
                 :ofct_disabled?, :ofct_no_policy?,
                 :obmb, :obmb_unconfigured?, :obmb_enabled?,
                 :obmb_disabled?, :obmb_no_policy?,
                 :obmw, :obmw_unconfigured?, :obmw_enabled?,
                 :obmw_disabled?, :obmw_no_policy?,
                 :aofo, :aofo_unconfigured?, :aofo_enabled?,
                 :aofo_disabled?, :aofo_no_policy?,
                 :ofo, :ofo_unconfigured?, :ofo_enabled?,
                 :ofo_disabled?, :ofo_no_policy?,
                 :grok_code, :grok_code_unconfigured?, :grok_code_enabled?,
                 :grok_code_disabled?, :grok_code_no_policy?,
                 to: :configuration


        # a_chat methods
        sig { override.params(force: T::Boolean).void }
        def a_chat_disabled!(force: false)
          return if a_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.a_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def a_chat_enabled!(force: false)
          return if a_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.a_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def a_chat_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.a_chat_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def a_chat_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).a_chat_no_policy? || T.must(copilot_business).a_chat_unconfigured?)
        end

        # g_chat methods
        sig { override.params(force: T::Boolean).void }
        def g_chat_disabled!(force: false)
          return if g_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.g_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def g_chat_enabled!(force: false)
          return if g_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.g_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def g_chat_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.g_chat_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def g_chat_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).g_chat_no_policy? || T.must(copilot_business).g_chat_unconfigured?)
        end

        # gtff methods
        sig { override.params(force: T::Boolean).void }
        def gtff_disabled!(force: false)
          return if gtff_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.gtff_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.gtff_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def gtff_enabled!(force: false)
          return if gtff_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.gtff_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.gtff_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def gtff_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.gtff_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def gtff_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).gtff_no_policy? || T.must(copilot_business).gtff_unconfigured?)
        end

        # o3 methods
        sig { override.params(force: T::Boolean).void }
        def o3_disabled!(force: false)
          return if o3_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.o3_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.o3_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def o3_enabled!(force: false)
          return if o3_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.o3_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.o3_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def o3_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.o3_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def o3_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).o3_no_policy? || T.must(copilot_business).o3_unconfigured?)
        end

        # obmb methods
        sig { override.params(force: T::Boolean).void }
        def obmb_disabled!(force: false)
          return if obmb_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmb_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmb_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def obmb_enabled!(force: false)
          return if obmb_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmb_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmb_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def obmb_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.obmb_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def obmb_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).obmb_no_policy? || T.must(copilot_business).obmb_unconfigured?)
        end

        # ofct methods
        sig { override.params(force: T::Boolean).void }
        def ofct_disabled!(force: false)
          return if ofct_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofct_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofct_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def ofct_enabled!(force: false)
          return if ofct_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofct_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofct_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def ofct_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.ofct_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def ofct_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).ofct_no_policy? || T.must(copilot_business).ofct_unconfigured?)
        end

        # obmw methods
        sig { override.params(force: T::Boolean).void }
        def obmw_disabled!(force: false)
          return if obmw_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmw_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmw_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def obmw_enabled!(force: false)
          return if obmw_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.obmw_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.obmw_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def obmw_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.obmw_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def obmw_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).obmw_no_policy? || T.must(copilot_business).obmw_unconfigured?)
        end

        # aofo methods
        sig { override.params(force: T::Boolean).void }
        def aofo_disabled!(force: false)
          return if aofo_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.aofo_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.aofo_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def aofo_enabled!(force: false)
          return if aofo_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.aofo_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.aofo_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def aofo_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.aofo_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def aofo_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).aofo_no_policy? || T.must(copilot_business).aofo_unconfigured?)
        end

        # ofo methods
        sig { override.params(force: T::Boolean).void }
        def ofo_disabled!(force: false)
          return if ofo_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofo_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofo_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def ofo_enabled!(force: false)
          return if ofo_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.ofo_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.ofo_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def ofo_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.ofo_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def ofo_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).ofo_no_policy? || T.must(copilot_business).ofo_unconfigured?)
        end

        # grok code methods
        sig { override.params(force: T::Boolean).void }
        def grok_code_disabled!(force: false)
          return if grok_code_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.grok_code_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(force: T::Boolean).void }
        def grok_code_enabled!(force: false)
          return if grok_code_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.grok_code_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def grok_code_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.grok_code_no_policy",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def grok_code_policy_inherited?
          return false unless copilot_business
          !(T.must(copilot_business).grok_code_no_policy? || T.must(copilot_business).grok_code_unconfigured?)
        end


        ###### END BASIC MODELS ######
      end
    end
  end
end
