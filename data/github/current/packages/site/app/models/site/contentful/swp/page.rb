# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        extend T::Helpers

        private

        sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.any(T.nilable(String), T.nilable(T::Boolean))]) }
        def settings(contentful_raw_json_response)
          maybe_page_settings = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
            entry.dig("sys", "contentType", "sys", "id") == "pageSettings"
          end

          maybe_global_navbar_style = maybe_page_settings.try(:dig, "fields", "globalNavbarStyle")

          {
            feature_flag: maybe_page_settings.try(:dig, "fields", "featureFlag"),
            use_dark_mode: maybe_page_settings.try(:dig, "fields", "colorMode") == "dark",
            revenue_play: maybe_page_settings.try(:dig, "fields", "revenuePlay"),
            global_navbar_style: (maybe_global_navbar_style.blank? || maybe_global_navbar_style == "default") ? nil : maybe_global_navbar_style
          }
        end

        sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.any(T.nilable(String), T.nilable(T::Boolean))]) }
        def seo(contentful_raw_json_response)
          maybe_page_seo = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
            entry.dig("sys", "contentType", "sys", "id") == "pageSeo"
          end

          return {} if maybe_page_seo.nil?

          maybe_social_media_image = (contentful_raw_json_response.dig("includes", "Asset") || []).find do |asset|
            asset.dig("sys", "id") == maybe_page_seo.dig("fields", "socialMediaImage").try(:dig, "sys", "id")
          end

          maybe_social_media_image_url = maybe_social_media_image.try(:dig, "fields", "file", "url")

          {
            description: maybe_page_seo.dig("fields", "description"),
            social_media_image: maybe_social_media_image_url.nil? ? nil : "https:#{maybe_social_media_image_url}",
            noindex_and_nofollow: maybe_page_seo.dig("fields", "noIndex") == true
          }
        end

        sig { params(path: String).returns(String) }
        def strip_path(path)
          path.gsub(/\.html\z/, "")
        end
      end
    end
  end
end
