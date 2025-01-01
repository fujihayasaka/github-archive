# typed: true
# frozen_string_literal: true

module Marketplace
  module Models
    module RenderDependency
      extend ActiveSupport::Concern
      extend T::Helpers

      include GitHub::Memoizer
      include Marketplace::Models::PlaygroundDependency
      include ReactHelper

      abstract!

      requires_ancestor { ApplicationController }

      sig { abstract.returns(T.nilable(User)) }
      def current_user; end

      memoize def renderable_model
        model_details(params[:registry], params[:model])
      end

      memoize def friendly_name
        renderable_model[:model][:friendly_name]
      end

      def render_model_show(force_ssr: true)
        payload = GitHubModels::Payloads::Show.new(
          current_user:,
          miniplayground_icebreaker: params[:p],
          model: renderable_model[:model],
          model_input_schema: renderable_model[:schema],
          params: params,
        ).call

        render_react_app(
          app_payload_generator: -> {
            {
              current_user: {
                login: current_user&.display_login,
                name: current_user&.name,
                avatarUrl: current_user&.primary_avatar_url(80),
                path: user_path(current_user)
              },
            }
          },
          payload: payload,
          ssr: force_ssr,
          page_data: {
            full_height: true,
            full_height_scrollable: false,
            footer: false,
            title: "#{friendly_name} · Models · GitHub Marketplace",
            description: "Create AI-powered applications with #{friendly_name}",
            richweb: {
              title: "#{friendly_name} · Models · GitHub Marketplace · GitHub",
              url: request&.original_url,
              description: "Create AI-powered applications with #{friendly_name}",
              image: model_family_image,
            },
          },
        )
      end

      def model_family_image
        family_name = renderable_model[:model][:model_family].downcase
        case family_name
        when "openai", "microsoft", "cohere", "meta"
          image_path("modules/marketplace/models/families/#{family_name}-hero.jpg")
        when "core42"
          image_path("modules/marketplace/models/families/#{family_name}-hero.png") # png
        when "ai21 labs"
          image_path("modules/marketplace/models/families/ai21labs-hero.jpg")
        when "mistral ai"
          image_path("modules/marketplace/models/families/mistral-hero.jpg")
        else
          image_path("modules/site/social-cards/home24.jpg") # Update with a models specific image when it's ready
        end
      end

      def check_user_can_view_model
        can_view = AzureModels::CatalogItem.can_view?(user: current_user, registry: params[:registry],
          name: params[:model])
        render_404 unless can_view
      end

      def set_marketplace_context_region
        context_region_preset :marketplace
      end

      MODELS_CLIENT_SIDE_FEATURE_FLAGS = [
        :project_neutron_presets_allow_images,
        :project_neutron_rag,
        :project_neutron_structured_outputs,
      ].freeze

      def add_models_client_side_feature_flags
        add_client_feature_flag(MODELS_CLIENT_SIDE_FEATURE_FLAGS)
      end
    end
  end
end
