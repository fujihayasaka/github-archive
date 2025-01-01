# typed: true
# frozen_string_literal: true

class OpenGraph::Scanner
  extend T::Sig

  OG_TITLE        = "og:title"
  OG_DESCRIPTION  = "og:description"
  OG_IMAGE        = "og:image"
  OG_SITE_NAME    = "og:site_name"
  OG_IMAGE_WIDTH  = "og:image:width"
  OG_IMAGE_HEIGHT = "og:image:height"

  TIMEOUT        = 3
  REDIRECT_LIMIT = 3
  MAX_RETRIES    = 2
  SERVICE_NAME   = "open_graph_scanner"

  FORCE_SSR = %w[twitter.com codepen.io]
  COMMON_SSR_USER_AGENT = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

  sig { params(url: String).void }
  def initialize(url)
    @url = url
  end

  sig { returns(OpenGraph::Scanner::Result) }
  def scan
    return Result.new unless valid_scheme?(url)

    resp = client.get(url)
    html = Nokogiri::HTML(resp.body)
    meta_tags = html.css("head meta[property^=og]")
      .map { |m| [m.attributes["property"].value, m.attributes["content"].value] }
      .to_h

    fallback_description = html.css("head meta[name=description]")
      .first&.attributes&.dig("content")&.value
    fallback_title = html.css("head title").first&.text

    tags = {
      url:          url,
      title:        meta_tags.dig(OG_TITLE) || fallback_title || "",
      description:  meta_tags.dig(OG_DESCRIPTION) || fallback_description || "",
      image:        meta_tags.fetch(OG_IMAGE, ""),
      site_name:    meta_tags.fetch(OG_SITE_NAME, ""),
      image_width:  meta_tags.fetch(OG_IMAGE_WIDTH, ""),
      image_height: meta_tags.fetch(OG_IMAGE_HEIGHT, ""),
    }

    Result.new(tags: tags, status: resp.status)
  rescue Faraday::Error, Nokogiri::XML::SyntaxError => e
    Result.new(error: e)
  end

  private

  attr_reader :url

  def client
    GitHub::FaradayClient::External.new do |conn|
      conn.options[:timeout] = TIMEOUT
      conn.request(:retry, max: MAX_RETRIES)
      conn.proxy = GitHub.external_communication_proxy_host
      conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use FaradayMiddleware::FollowRedirects, limit: REDIRECT_LIMIT
      if force_ssr?
        conn.headers["User-Agent"] = COMMON_SSR_USER_AGENT
      end
      conn.adapter(Faraday.default_adapter)
    end
  end

  def valid_scheme?(url)
    scheme = URI.parse(url).scheme
    if external_url?(url)
      scheme.in?(%w[https])
    else
      scheme == GitHub.scheme
    end
  end

  def external_url?(url)
    URI.parse(url).host != GitHub.host_name
  end

  def force_ssr?
    URI.parse(url).host.in?(FORCE_SSR)
  end
end
