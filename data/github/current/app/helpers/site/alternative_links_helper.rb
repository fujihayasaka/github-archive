# typed: true
# frozen_string_literal: true

module Site::AlternativeLinksHelper
  include ActionView::Helpers::TagHelper
  include Site::SeoHelper

  # Returns all alternate link tags for all available locales (each with locale param)
  # Preserves canonical parameters like page numbers
  def alternate_link_tags(request)
    locales = ::Localization::Config.new.available_locales
    original_url = request.original_url

    # Generate alternate links for each locale
    locale_links = locales.map do |loc|
      url = canonical_url_for(original_url, loc)
      tag(:link, rel: "alternate", hreflang: loc.downcase, href: url)
    end

    # Add x-default link (pointing to English version)
    canonical_params = extract_canonical_params(request.query_parameters.to_h)
    x_default_uri = URI.parse(original_url)
    x_default_uri.query = canonical_params.empty? ? nil : canonical_params.to_query
    x_default_link = tag(:link, rel: "alternate", hreflang: "x-default", href: x_default_uri.to_s)

    safe_join(locale_links + [x_default_link], "\n")
  end
end
