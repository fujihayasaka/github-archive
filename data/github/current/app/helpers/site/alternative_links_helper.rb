# typed: true
# frozen_string_literal: true

module Site::AlternativeLinksHelper
  include ActionView::Helpers::TagHelper

  # Returns all alternate link tags for all available locales (each with locale param)
  def alternate_link_tags(request)
    locales = ::Localization::Config.new.available_locales
    locales.map do |loc|
      next if loc.to_s.downcase == "en"

      uri = URI.parse(request.original_url)
      uri.query = URI.encode_www_form([["locale", loc]])

      tag(:link, rel: "alternate", hreflang: loc.downcase, href: uri.to_s)
    end.join("\n").html_safe # rubocop:disable Rails/OutputSafety
  end
end
