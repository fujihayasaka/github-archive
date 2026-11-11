# typed: true
# frozen_string_literal: true

class Site::Resources::ArticlesController < Site::Resources::BaseController
  include Site::BreadcrumbDependency
  around_action :switch_locale, only: [:index, :show]
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze

  stylesheet_bundle "resources"

  def index
    page_params = {
      path: "/resources/articles",
      locale: user_locale,
      url: request.url,
      query: request.query_parameters,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::Core::Pages::IndexPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page.feature_flag)

    render_react_app(
      payload: {
        contentfulRawJsonResponse: page.refined_view_data,
        userLoggedIn: logged_in?,
        additionalProps: {
          filters: page.grouped_filters,
          totalPages: page.total_pages,
          sortOptions: page.sort_options_with_values,
          currentSort: page.current_sort_value,
          showSpotlightCard: page.show_spotlight_card,
        },
      },
      title: page.title,
      page_data: page.options,
    )
  end

  def show
    slug = params[:topic]

    page_params = {
      path: "/resources/articles/#{slug}",
      locale: user_locale,
      url: request.url,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::ContainerPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page.feature_flag)

    add_breadcrumb "Articles", "/resources/articles"
    add_breadcrumb page.title, "/resources/articles/#{slug}"

    react_render_params = {
      app_payload_generator: app_payload_generator,
      payload: {
        contentfulRawJsonResponse: page.view_data,
        userLoggedIn: logged_in?,
        breadcrumbLinks: breadcrumbs,
        indexPath: "/resources/articles",
      },
      title: page.title,
      page_data: { **page.options },
    }.compact

    render_react_app(**react_render_params)
  end

  private def hidden?(feature_flag)
    return false if feature_flag.blank?

    !FeatureFlag.vexi.enabled?(feature_flag, current_user, default: false)
  end



  private def app_payload_generator
    lambda do
      {
        octocaptchaHost: GitHub.urls.octocaptcha_host_name,
        marketingFormsApiHost: GitHub.marketing_forms_api_host_url,
        marketingTargetedCountries: marketing_targeted_countries
      }
    end
  end
end
