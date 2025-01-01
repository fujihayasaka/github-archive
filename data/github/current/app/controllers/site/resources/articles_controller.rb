# typed: true
# frozen_string_literal: true

class Site::Resources::ArticlesController < Site::Resources::BaseController
  include ReactHelper
  include Site::Contentful::Marketing::Resources::AvailableTopics
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  before_action :validate_topic
  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
  }.freeze

  stylesheet_bundle "resources"

  def index
    render_404 and return unless lp_seo_pages?

    # this method also handles the 'All topics' filter where topic is blank
    topic = params[:topic].present? ? params[:topic] : ""

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::CategoryPage, topic: topic, page: params[:page], url: request&.url)

    page = Site::Contentful::Marketing::Resources::Pages::CategoryPage.new(topic: topic, page: params[:page], url: request&.url)

    render_404 and return if page.page_number <= 0 || page.contentful_response.nil?

    page.filter_hidden_pages { |ff| hidden?(ff) }
    page.apply_pagination

    render_404 and return if page.contentful_response["items"].empty?

    render_react_app(
      payload: {
        contentfulRawJsonResponse: page.contentful_response,
        userLoggedIn: logged_in?,
        additionalProps: { pageHeading: page.topic_name, page: page.page_number, totalPages: page.total_pages }
      },
      page_data: page.page_data,
      title: page.topic_name,
      ssr: true,
    )
  end

  def show
    render_404 and return unless lp_seo_pages?

    slug = "#{params[:topic]}/#{params[:path]}"

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::ShowPage, slug: slug, url: request&.url)

    page = Site::Contentful::Marketing::Resources::Pages::ShowPage.new(slug: slug, url: request&.url)

    render_404 and return if page.contentful_response.nil? || page.contentful_response["items"].empty? || hidden?(page.feature_flag)

    render_react_app(
      payload: { contentfulRawJsonResponse: page.contentful_response, userLoggedIn: logged_in? },
      title: page.title,
      page_data: page.page_data,
      ssr: true,
    )
  end

  private def hidden?(feature_flag)
    feature_flag.present? && !feature_enabled_globally_or_for_current_user?(feature_flag)
  end

  private def lp_seo_pages?
    feature_enabled_globally_or_for_current_user?(:contentful_lp_seo_pages)
  end

  private def validate_topic
    render_404 unless AVAILABLE_TOPICS.key?(params[:topic]) || params[:topic].blank?
  end
end
