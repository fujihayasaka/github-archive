# typed: true
# frozen_string_literal: true

class Site::SitemapMarketingController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Sitemap)
    sitemap_urls = generate_sitemap_urls
    render_sitemap(sitemap_urls)
  end

  private def generate_sitemap_urls
    sitemap_urls = []
    sitemap_urls.concat(marketing_urls, resources_index_urls, dynamic_urls)
    format_sitemap_urls(sitemap_urls)
  end

  private def format_sitemap_urls(sitemap_urls)
    sitemap_urls.map { |url| { loc: url[:loc].sub("www.", "") } }
  end

  private def marketing_urls
    Site::Sitemap::MARKETING_URLS.map { |url| { loc: url } }
  end

  private def resources_index_urls
    resources_index_urls = Site::Contentful::Marketing::Resources::AvailableTopics.available_public_topics.map do |topic|
      { loc: "https://github.com/resources/articles/#{topic}" }
    end

    # Add all topics index page
    resources_index_urls << { loc: "https://github.com/resources/articles" }
  end

  private def dynamic_urls
    url_flag_pairs = Site::Contentful::Marketing::Resources::Pages::Sitemap.new
    filtered_url_flag_pairs = url_flag_pairs.filter_hidden_urls { |ff| hidden?(ff) }
    filtered_url_flag_pairs.map { |url| { loc: url[:path] } }
  end

  private def render_sitemap(sitemap_urls)
    xml = sitemap_urls.to_xml(root: "urlset", children: "url", skip_types: true, dasherize: false)
    xml_with_namespace = xml.sub("<urlset>", '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')

    respond_to do |format|
      format.xml { render xml: xml_with_namespace }
    end
  end

  private def hidden?(feature_flag)
    feature_flag.present? && !feature_enabled_globally_or_for_current_user?(feature_flag)
  end
end
