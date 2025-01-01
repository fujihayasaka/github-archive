# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module ModelAccess
      extend T::Helpers
      include Copilot::Users::Signatures


      FREE_MODELS = T.let([
        :a_chat, # Anthropic Claude 3.5
        :o3, # OpenAI o3
        :g_chat, # Google Gemini 2.0
        :gtff, # Google Gemini 2.5 Flash
        :ofo, # OpenAI GPT-4.1
      ], T::Array[Symbol])

      PRO_MODELS = T.let([
        *FREE_MODELS,
        :a_f, # Anthropic Claude 3.7
        :afos, # Anthropic Clause 4.0 Sonnet
        :g_tf, # Google Gemini 2.5
        :o1, # OpenAI o1
        :o_fm, # OpenAI 4-mini
      ], T::Array[Symbol])

      PRO_PLUS_MODELS = T.let([
        *PRO_MODELS,
        :o_ff, # OpenAI GPT-4.5
        :o_t,  # OpenAI o3
        :al,   # Anthropic Claude 4.0 Opus
      ], T::Array[Symbol])

      abstract!
      sig { params(copilot_user: Copilot::User, model: Symbol).returns(T::Boolean) }
      def self.model_available?(copilot_user, model)
        if copilot_user.has_pro_plus_access?
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
