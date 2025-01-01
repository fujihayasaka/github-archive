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

      sig { returns(GitHubModels::Types::Model) }
      attr_reader :model

      sig { returns(T.nilable(GitHubModels::Types::ModelSchema)) }
      attr_reader :model_input_schema

      sig { override.returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(ActionController::Parameters) }
      attr_reader :params

      sig do
        params(
          model: GitHubModels::Types::Model,
          current_user: T.nilable(User),
          model_input_schema: T.nilable(GitHubModels::Types::ModelSchema),
          miniplayground_icebreaker: T.nilable(String),
          params: ActionController::Parameters,
        ).void
      end
      def initialize(model:, current_user:, model_input_schema:, miniplayground_icebreaker:, params:)
        @model = model
        @model_input_schema = model_input_schema
        @current_user = current_user
        @miniplayground_icebreaker = miniplayground_icebreaker
        @params = params
      end

      sig do
        returns({
          model: GitHubModels::Types::Model,
          modelEvaluation: String,
          modelInputSchema: T.nilable(GitHubModels::Types::ModelSchema),
          modelTransparencyContent: String,
          modelReadme: String,
          readmeToc: T::Array[GitHubModels::Types::MarkdownTocItem],
          playgroundUrl: String,
          gettingStarted: T::Hash[Symbol, T.untyped],
          miniplaygroundIcebreaker: T.nilable(String),
          modelLicense: String,
          canProvideAdditionalFeedback: T::Boolean,
          isLoggedIn: T::Boolean,
          canUseO1Models: T::Boolean,
          comparedModelDetails: T.nilable(GitHubModels::Types::ModelDetails),
          appliedPreset: T.nilable(GitHubModels::Types::Preset),
        })
      end
      def call
        {
          model: model,
          modelEvaluation: render_evaluation,
          modelInputSchema: model_input_schema,
          modelReadme: render_description.output,
          readmeToc: render_description[:toc_headers_hash],
          modelTransparencyContent: render_notes,
          playgroundUrl: GitHub.azure_ai_playground_url + "/chat/completions",
          gettingStarted: getting_started_table_of_contents(model),
          miniplaygroundIcebreaker: @miniplayground_icebreaker,
          modelLicense: render_license,
          canProvideAdditionalFeedback: can_provide_additional_feedback?,
          isLoggedIn: current_user.present?,
          canUseO1Models: can_use_o1_models?(current_user),
          comparedModelDetails: compared_model_details,
          appliedPreset: applied_preset,
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
        # If the current user belongs to an entity that is on a Copilot Business or Copilot Enterprise plan, we don't allow them to send any user data including free text and whether or not they can be contacted by us
        return false if current_user.nil?
        copilot_user = Copilot::User.new(T.must(current_user))
        return false if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
        return false if T.must(current_user).organizations.any? { |org| Copilot::Organization.new(org).copilot_enabled? }
        return false if T.must(current_user).businesses.any? { |bus| Copilot::Business.new(bus).copilot_enabled? }

        true
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
