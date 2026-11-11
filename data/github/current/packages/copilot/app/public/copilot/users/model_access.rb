# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module ModelAccess
      extend T::Helpers
      include Copilot::Users::Signatures


      FREE_MODELS = T.let([
        :o3, # OpenAI o3-mini
        :gtff, # Google Gemini 2.5 Flash
        :ofo, # OpenAI GPT-4.1
        :obmw, # OpenAI GPT-5 mini
        :m_ironman, # Emergency Free Model
      ], T::Array[Symbol])

      PRO_MODELS = T.let([
        *FREE_MODELS,
        :afos, # Anthropic Clause 4.0 Sonnet
        :arcticfox, # OpenAI GPT-5.1-Codex-Max
        :antman, # Emergency Pro Model
        :bento, # Anthropic Claude Haiku 4.5
        :blackpanther, # Emergency Pro Model
        :blueberry, # Google Gemini 3 Flash
        :captainamerica, # Emergency Pro Model
        :cherry, # TODO
        :cucumber, # TODO
        :daisy, # Anthropic Daisy
        :g_tf, # Google Gemini 2.5
        :grok_code, # xAI Grok Code Fast 1
        :lotus, # Anthropic Claude Opus 4.5
        :m_spiderman, # OpenAI GPT-5.1-Codex
        :m_thor, # OpenAI GPT-5.1-Codex-Mini
        :o1, # OpenAI o1
        :obmb, # OpenAI GPT-5
        :ofct, # OpenAI GPT-5-Codex
        :sunflower, # OpenAI GPT-5.1
        :tulip, # Google Gemini 3 Pro
        :hulk, # Emergency Pro Model
        :wintersoldier, # Emergency Pro Model
        :watermelon, # OpenAI GPT-5.2
      ], T::Array[Symbol])

      PRO_PLUS_MODELS = T.let([
        *PRO_MODELS,
        :o_ff, # OpenAI GPT-4.5
        :aofo, # Anthropic Claude 4.1 Opus
      ], T::Array[Symbol])

      MAX_MODELS = T.let([
        *PRO_PLUS_MODELS,
      ], T::Array[Symbol])

      abstract!
      sig { params(copilot_user: Copilot::User, model: Symbol).returns(T::Boolean) }
      def self.model_available?(copilot_user, model)
        if copilot_user.has_max_access?
          return true if MAX_MODELS.include?(model)
        elsif copilot_user.has_pro_plus_access?
          return true if PRO_PLUS_MODELS.include?(model)
        elsif copilot_user.has_pro_access?
          return true if PRO_MODELS.include?(model)
        elsif copilot_user.has_ci_access? && !copilot_user.has_limited_access?
          return true if PRO_MODELS.include?(model)
        elsif copilot_user.has_limited_access?
          return true if FREE_MODELS.include?(model)
        end
        false
      end

      sig { params(copilot_user: Copilot::User, model: Symbol).returns(T::Boolean) }
      def self.model_unavailable?(copilot_user, model)
        !model_available?(copilot_user, model)
      end
    end
  end
end
