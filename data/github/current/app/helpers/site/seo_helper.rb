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

  sig { params(url: String).returns(T.nilable(String)) }
  def canonical_url_for(url)
    uri = URI.parse(url)

    return unless %w(http https).include?(uri.scheme)

    canonical_url = "#{uri.scheme}://#{uri.host}#{uri.path}"
    canonical_url = canonical_url.chop if canonical_url.ends_with?("/")

    query_params = URI.decode_www_form(uri.query.to_s).to_h

    canonical_params = {}

    page = query_params["page"].to_i
    canonical_params["page"] = page if page > 1

    # Temporary fix to make GitHub models catalog improve its SEO search results.
    type = query_params["type"]
    canonical_params["type"] = type if type.to_s.match?(/models/)

    unless canonical_params.empty?
      canonical_url += "?#{canonical_params.to_query}"
    end

    canonical_url

  rescue URI::InvalidURIError
  end
end
