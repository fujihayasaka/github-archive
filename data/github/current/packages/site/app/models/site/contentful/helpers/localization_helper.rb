# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Helpers
      module LocalizationHelper
        # Given a locale as defined for I18n.available_locales, will return the local as defined in Contentful.
        sig { params(locale: Symbol).returns(String) }
        def contentful_locale(locale)
          {
            ko: "ko-KR",
            en: "en-US",
            pt: "pt-BR",
            es: "es-419",
            ja: "ja",
          }.fetch(locale, "en-US")
        end

        sig { params(data: T::Hash[String, T.untyped], locale: String).returns(T::Hash[String, T.untyped]) }
        def localize_github_links(data, locale)
          (data.dig("includes", "Entry") || []).each do |entry|
            next if !entry["fields"]

            entry["fields"].each do |key, val|

              # Link fields e.g. the href of an image component.
              if %w[href url].include?(key)
                if val.is_a?(String)
                  new_url = localize_single_line_text(val, locale)
                  entry["fields"][key] = new_url
                end

              # Richtext
              elsif val.is_a?(Hash) && val["nodeType"] == "document"
                entry["fields"][key] = localize_richtext(val, locale)
              end
            end

            entry
          end

          data
        end

        private

        sig { params(value: String, locale: String).returns(String) }
        def localize_single_line_text(value, locale)
          uri = URI.parse(value)

          # Check if the URL has github.com as host
          if uri.host&.casecmp("github.com")&.zero?
            query_params = URI.decode_www_form(uri.query || "").to_h
            query_params["locale"] = locale
            uri.query = URI.encode_www_form(query_params)
            uri.to_s
          else
            value
          end
        rescue URI::InvalidURIError
          value
        end

        sig { params(data: T::Hash[String, T.untyped], locale: String).returns(T::Hash[String, T.untyped]) }
        def localize_richtext(data, locale)
          # If it's a link node, localize the URL
          if data["nodeType"] == "hyperlink"
            uri = data.dig("data", "uri")
            if uri.is_a?(String)
              data["data"]["uri"] = localize_single_line_text(uri, locale)
            end
          # If it has children, process the children
          elsif data["content"].is_a?(Array)
            data["content"].each do |item|
              localize_richtext(item, locale)
            end
          end

          data
        end

      end
    end
  end
end
