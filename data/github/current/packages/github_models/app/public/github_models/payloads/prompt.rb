# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class Prompt
      # Keep in sync with `PromptAppPayload` in ui/packages/github-models-repo/routes/prompt/types.ts
      GitHubModelsPromptPayload = T.type_alias do
        {
          inferenceUrl: String,
          restrictedModels: T::Array[String],
          improvedSysPromptModel: T.nilable(DefaultAndCustomModels::Types::Model),
          prompt: T.nilable(String),
          promptPath: T.nilable(String),
          promptRef: T.nilable(String),
          repository: T::Hash[Symbol, T.untyped],
          commitInfo: T::Hash[Symbol, T.untyped],
          canEdit: T::Boolean,
          paidUsageBannerDismissed: T::Boolean,
          businessSlug: T.nilable(String),
          userSettings: T::Hash[String, T.untyped],
          rateLimitLink: String,
        }
      end

      include OcticonsHelper
      include GitHub::Memoizer

      sig do
        params(
          models_user: GitHubModels::User,
          improved_sys_prompt_model: T.nilable(DefaultAndCustomModels::Types::Model),
          prompt: T.nilable(String),
          prompt_path: T.nilable(String),
          prompt_ref: T.nilable(String),
          repository: T::Hash[Symbol, T.untyped],
          commit_info: T::Hash[Symbol, T.untyped],
          can_edit: T::Boolean,
          inference_url: String,
          paid_usage_banner_dismissed: T::Boolean,
          business_slug: T.nilable(String),
          user_settings: T::Hash[String, T.untyped],
          rate_limit_link: String,
        ).void
      end
      def initialize(
        models_user:,
        improved_sys_prompt_model:,
        prompt:,
        prompt_path:,
        prompt_ref:,
        repository:,
        commit_info:,
        can_edit:,
        inference_url:,
        paid_usage_banner_dismissed:,
        business_slug:,
        user_settings:,
        rate_limit_link:
      )
        @models_user = models_user
        @improved_sys_prompt_model = improved_sys_prompt_model
        @prompt = prompt
        @prompt_path = prompt_path
        @prompt_ref = prompt_ref
        @repository = repository
        @commit_info = commit_info
        @can_edit = can_edit
        @inference_url = inference_url
        @paid_usage_banner_dismissed = paid_usage_banner_dismissed
        @business_slug = business_slug
        @user_settings = user_settings
        @rate_limit_link = rate_limit_link
      end

      sig { returns(GitHubModelsPromptPayload) }
      def call
        {
          inferenceUrl: @inference_url,
          restrictedModels: @models_user.restricted_models,
          improvedSysPromptModel: @improved_sys_prompt_model,
          prompt: @prompt,
          promptPath: @prompt_path,
          promptRef: @prompt_ref,
          repository: @repository,
          commitInfo: @commit_info,
          canEdit: @can_edit,
          paidUsageBannerDismissed: @paid_usage_banner_dismissed,
          businessSlug: @business_slug,
          userSettings: @user_settings,
          rateLimitLink: @rate_limit_link,
        }
      end
    end
  end
end
