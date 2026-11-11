# typed: true
# frozen_string_literal: true

module Site::AlternativeLinksHelper
  include ActionView::Helpers::TagHelper
  include Site::SeoHelper

  # Returns all alternate link tags for all enabled locales (each with locale param).
  # Preserves canonical parameters like page numbers.
  # Locales gated by a feature flag are excluded when the flag is off,
  # so crawlers won't see hreflang for un-launched locales.
  def alternate_link_tags(request)
    locales = ::Localization::Config.new.available_locales
    original_url = request.original_url

    # Generate alternate links only for enabled locales
    locale_links = locales.filter_map do |loc|
      next unless MarketingLocales.locale_enabled?(loc, nil)

      normalized_loc = normalize_locale(loc)
      url = canonical_url_for(original_url, normalized_loc)
      tag(:link, rel: "alternate", hreflang: normalized_loc.downcase, href: url)
    end

    # Add x-default link (pointing to English version)
    canonical_params = extract_canonical_params(request.query_parameters.to_h)
    x_default_uri = URI.parse(original_url)
    x_default_uri.query = canonical_params.empty? ? nil : canonical_params.to_query
    x_default_link = tag(:link, rel: "alternate", hreflang: "x-default", href: x_default_uri.to_s)

    safe_join(locale_links + [x_default_link], "\n")
  end
end
