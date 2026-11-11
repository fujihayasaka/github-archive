# typed: true
# frozen_string_literal: true

module Site::SeoHelper
  include ActionView::Helpers::TagHelper

  def dont_index
    tag :meta, name: "robots", content: "noindex, follow"
  end

  def dont_index_or_follow
    tag :meta, name: "robots", content: "noindex, nofollow"
  end

  sig { params(url: String, locale: String).returns(T.nilable(String)) }
  def canonical_url_for(url, locale = "en")
    uri = URI.parse(url)

    return unless %w(http https).include?(uri.scheme)

    canonical_url = "#{uri.scheme}://#{uri.host}#{uri.path}"
    canonical_url = canonical_url.chop if canonical_url.ends_with?("/")

    query_params = URI.decode_www_form(uri.query.to_s).to_h

    canonical_params = extract_canonical_params(query_params, locale)

    unless canonical_params.empty?
      canonical_url += "?#{canonical_params.to_query}"
    end

    canonical_url
  rescue URI::InvalidURIError
  end

  sig { params(query_params: T::Hash[String, T.untyped], locale: String).returns(T::Hash[String, T.untyped]) }
  def extract_canonical_params(query_params, locale = "en")
    kept_params = {}

    # Keep page parameter if greater than 1
    page = query_params["page"].to_i
    kept_params["page"] = page if page > 1

    # Keep type parameter for models
    type = query_params["type"]
    kept_params["type"] = type if type.to_s.match?(/models/)

    # Include locale in canonical params if it is not the default locale
    if locale.present? && locale.downcase != "en"
      kept_params["locale"] = locale
    end

    kept_params
  end
end
