# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        module Options
          extend T::Helpers
          include Settings
          include Seo

          abstract!

          sig { abstract.returns(String) }
          def url; end

          sig { params(additional_options: T::Hash[Symbol, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
          def options(additional_options = {})
            {
              **dark_mode_opts,
              **seo_opts,
              **global_navbar_opts,
              revenue_play:,
            }.deep_merge(additional_options).compact
          end

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def dark_mode_opts
            use_dark_mode? ? { class: "header-dark", marketing_footer_theme: "dark" } : {}
          end

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def seo_opts
            # Extract socialMediaImage link and resolve it to get the Asset
            social_media_image_id = seo&.dig("socialMediaImage", "sys", "id")
            social_media_image_asset = social_media_image_id ? find_link(social_media_image_id, type: "Asset") : nil
            social_media_image_url = social_media_image_asset&.dig("fields", "file", "url")
            {
              description: seo&.fetch("description", nil),
              noindex_and_nofollow: seo&.fetch("noIndex", false),
              richweb: {
                description: seo&.fetch("description", nil),
                image: social_media_image_url.nil? ? nil : "https:#{social_media_image_url}",
                title: get_field("title"),
                url:,
              }
            }
          end

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def global_navbar_opts
            case global_navbar_style
            when "white"
              { class: "header-white" }
            when "light transparent"
              { class: "header-white header-overlay" }
            when "black"
              { class: "header-dark" }
            when "dark transparent"
              { class: "header-overlay" }
            else
              {}
            end
          end
        end
      end
    end
  end
end
