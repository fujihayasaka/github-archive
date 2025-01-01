# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    module Models
      class Show
        extend T::Sig
        include OcticonsHelper
        include GitHub::Memoizer
        include UrlHelpers
        include ::BlobMarkupHelper

        sig { returns(Marketplace::Types::AzureModels::Model) }
        attr_reader :model

        sig { returns(T.nilable(Marketplace::Types::AzureModels::ModelSchema)) }
        attr_reader :model_input_schema

        sig { returns(T.nilable(User)) }
        attr_reader :current_user

        sig { returns(T::Boolean) }
        attr_reader :on_waitlist

        sig do
          params(
            model: Marketplace::Types::AzureModels::Model,
            current_user: T.nilable(User),
            model_input_schema: T.nilable(Marketplace::Types::AzureModels::ModelSchema),
            miniplayground_icebreaker: T.nilable(String),
          ).void
        end
        def initialize(model:, current_user:, model_input_schema:, miniplayground_icebreaker:)
          @model = model
          @model_input_schema = model_input_schema
          @current_user = current_user
          @on_waitlist = T.let(current_user_on_waitlist?, T::Boolean)
          @miniplayground_icebreaker = miniplayground_icebreaker
        end

        sig do
          returns({
            model: Marketplace::Types::AzureModels::Model,
            modelEvaluation: String,
            modelInputSchema: T.nilable(Marketplace::Types::AzureModels::ModelSchema),
            modelTransparencyContent: String,
            modelReadme: String,
            readmeToc: T::Array[Marketplace::Types::AzureModels::MarkdownTocItem],
            playgroundUrl: String,
            on_waitlist: T::Boolean,
            gettingStarted: T::Hash[Symbol, T.untyped],
            miniplaygroundIcebreaker: T.nilable(String),
            modelLicense: String,
            canProvideAdditionalFeedback: T::Boolean,
            isLoggedIn: T::Boolean
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
            playgroundUrl: GitHub.azure_ai_playground_url,
            on_waitlist: on_waitlist,
            gettingStarted: getting_started_table_of_contents,
            miniplaygroundIcebreaker: @miniplayground_icebreaker,
            modelLicense: render_license,
            canProvideAdditionalFeedback: can_provide_additional_feedback?,
            isLoggedIn: current_user.present?
          }
        end

        private

        # Generated a simplified table of contents for this model's getting
        # started content, with just the language and SDK names.
        # {
        #   [language]: {
        #     name: String,
        #     sdks: {
        #       [sdk_id]: {
        #         name: String,
        #         content: String,
        #         tocHeadings: Array,
        #         codeSamples: String,
        #       }
        #     }
        #   }
        # }
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def getting_started_table_of_contents
          getting_started_content_entry.each_with_object({}) do |(language, language_entry), acc|
            acc[language] = {
              name: language_entry[:"name"],
              sdks: language_entry[:"sdks"].each_with_object({}) do |(sdk, sdk_entry), sdkacc|
                content = getting_started_content(language: language, sdk: sdk)
                sdkacc[sdk] = {
                  name: sdk_entry[:"name"],
                  content: content.output,
                  tocHeadings: content[:toc_headers_hash],
                  codeSamples: sdk_entry[:"code_sample"],
                }
              end
            }
          end
        end

        # returns { [model_id]: { [language]: { [sdk]: String } }
        sig { returns(T::Hash[Symbol, T.untyped]) }
        memoize def getting_started_content_entry
          # Can't use the actual model[:id] here because it includes a version number,
          # whereas the toc.json file omits it.
          model_id = "azureml://registries/#{model[:registry]}/models/#{model[:original_name]}"
          content_entry = Marketplace::Payloads::Models::GettingStartedContent.fetch(model_id.to_sym)
          raise ArgumentError unless content_entry
          content_entry
        end

        # Returns the content for the getting started guide, based on the
        # language and SDK specified in the params. If no language or SDK is
        # passed, it defaults to the first language and the first SDK in that
        # language. If the language or SDK is not found, it raises an
        # ArgumentError which causes the controller to 404.
        sig { params(language: Symbol, sdk: Symbol).returns(GitHub::HTML::Result) }
        def getting_started_content(language:, sdk:)
          language_entry = getting_started_content_entry[language]

          raise ArgumentError if language_entry.nil?

          sdks = language_entry[:"sdks"]
          raise ArgumentError if sdks[sdk].nil?
          content = sdks[sdk][:"content"]

          context = {
            anchor_icon: octicon("link"), # rubocop:disable Primer/PrimerOcticon
          }

          GitHub::Goomba::ModelsMarkdownPipeline.call(content,
            context,
            cache_settings: { use_cache: true },
          )
        end

        sig { returns(T::Boolean) }
        def current_user_on_waitlist?
          return false unless current_user.present?

          EarlyAccessMembership.on_waitlist?(::Marketplace::ModelsBeta.new.feature_slug, T.must(current_user))
        end

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
      end
    end
  end
end
