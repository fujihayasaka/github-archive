# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class Show
      include OcticonsHelper
      include GitHub::Memoizer
      include UrlHelpers
      include ::BlobMarkupHelper
      include Marketplace::Models::PlaygroundDependency
      include ResilienceHelper

      sig { returns(GitHubModels::Types::Model) }
      attr_reader :model

      sig { returns(T.nilable(GitHubModels::Types::ModelSchema)) }
      attr_reader :model_input_schema

      sig { override.returns(T.nilable(::User)) }
      attr_reader :current_user

      sig { returns(ActionController::Parameters) }
      attr_reader :params

      sig do
        params(
          model: GitHubModels::Types::Model,
          current_user: T.nilable(::User),
          model_input_schema: T.nilable(GitHubModels::Types::ModelSchema),
          miniplayground_icebreaker: T.nilable(String),
          prompt_extraction_code_snippet: T.nilable(String),
          params: ActionController::Parameters,
          improved_prompt_model: T.nilable(GitHubModels::Types::Model),
          prompt_extraction_model: T.nilable(GitHubModels::Types::Model)
        ).void
      end
      def initialize(model:, current_user:, model_input_schema:, miniplayground_icebreaker:, prompt_extraction_code_snippet:, params:, improved_prompt_model:, prompt_extraction_model:)
        @model = model
        @model_input_schema = model_input_schema
        @current_user = current_user
        @miniplayground_icebreaker = miniplayground_icebreaker
        @params = params
        @prompt_extraction_code_snippet = prompt_extraction_code_snippet
        @improved_prompt_model = improved_prompt_model
        @prompt_extraction_model = prompt_extraction_model
      end

      sig { returns(GitHubModels::Types::ShowPayload) }
      def call
        github_models_user = GitHubModels::User.new(user: current_user)
        {
          model: model,
          modelEvaluation: render_evaluation,
          modelInputSchema: model_input_schema,
          modelReadme: render_description.output,
          readmeToc: readme_toc,
          modelTransparencyContent: render_notes,
          playgroundUrl: github_models_user.playground_url,
          gettingStarted: getting_started_table_of_contents(model, model_input_schema),
          miniplaygroundIcebreaker: @miniplayground_icebreaker,
          modelLicense: render_license,
          canProvideAdditionalFeedback: can_provide_additional_feedback?,
          isLoggedIn: current_user.present?,
          restrictedModels: github_models_user.restricted_models,
          comparedModelDetails: compared_model_details,
          appliedPreset: applied_preset,
          promptExtractionCodeSnippet: @prompt_extraction_code_snippet,
          improvedPromptModel: @improved_prompt_model,
          promptExtractionModel: @prompt_extraction_model,
          promptFeedbackBannerDismissed: current_user&.dismissed_notice?(:github_models_prompt_feedback_banner),
          playgroundFeedbackPopoverDismissed: current_user&.dismissed_notice?(:github_models_playground_feedback_popover),
        }
      end

      private

      sig do
        returns(GitHub::HTML::Result)
      end
      memoize def render_description
        context = {
          anchor_icon: octicon("link"), # rubocop:disable Primer/PrimerOcticon
        }

        GitHub::Goomba::ModelsMarkdownPipeline.call(model[:description], context, cache_settings: { use_cache: true })
      end

      sig { returns T::Array[GitHubModels::Types::MarkdownTocItem] }
      def readme_toc
        render_description[:toc_headers_hash]
      end

      sig do
        returns(String)
      end
      def render_notes
        GitHub::Goomba::ModelsMarkdownPipeline.to_html(model[:notes])
      end

      sig do
        returns(String)
      end
      def render_license
        return "" unless model[:license_description].present?

        rendered_license = GitHub::Goomba::DescriptionPipeline.to_html(model[:license_description])

        plaintext_blob_content rendered_license
      end

      sig do
        returns(String)
      end
      def render_evaluation
        GitHub::Goomba::ModelsMarkdownPipeline.to_html(model[:evaluation])
      end

      sig { returns(T::Boolean) }
      def can_provide_additional_feedback?
        current_user = self.current_user
        # If the current user belongs to an entity that is on a Copilot Business or Copilot Enterprise plan, we don't allow them to send any user data including free text and whether or not they can be contacted by us
        return false if current_user.nil?
        copilot_user = Copilot::User.new(current_user)
        return false if has_cfb_or_cfe_access?(copilot_user)
        return false if does_any_user_org_have_copilot?
        return false if does_any_user_business_have_copilot?

        true
      end

      sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
      def has_cfb_or_cfe_access?(copilot_user)
        with_database_error_fallback(fallback: false) do
          copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
        end
      end

      sig { returns T::Boolean }
      def does_any_user_org_have_copilot?
        current_user = self.current_user
        return false unless current_user

        current_user.organizations.any? do |org|
          copilot_org = Copilot::Organization.new(org)
          with_database_error_fallback(fallback: false) { copilot_org.copilot_enabled? }
        end
      end

      sig { returns T::Boolean }
      def does_any_user_business_have_copilot?
        current_user = self.current_user
        return false unless current_user

        current_user.businesses.any? do |business|
          copilot_business = Copilot::Business.new(business)
          with_database_error_fallback(fallback: false) { copilot_business.copilot_enabled? }
        end
      end

      sig { returns(T.nilable(GitHubModels::Types::ModelDetails)) }
      def compared_model_details
        return unless params[:compare_to].present?

        renderable_side_model(params[:compare_to])
      end

      sig { returns(T.nilable(GitHubModels::Types::Preset)) }
      def applied_preset
        return unless params[:preset].present?

        renderable_preset(params[:preset])
      end
    end
  end
end
