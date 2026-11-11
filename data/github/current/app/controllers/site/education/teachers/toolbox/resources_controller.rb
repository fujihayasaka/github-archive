# typed: true
# frozen_string_literal: true

class Site::Education::Teachers::Toolbox::ResourcesController < Site::BaseController
  include Site::BreadcrumbDependency
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = T.let({
    connect_src: [GitHub.marketing_forms_api_host_url],
    frame_src: [GitHub.urls.octocaptcha_host_name, "https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze, T::Hash[T.untyped, T.untyped])

  stylesheet_bundle "resources"

  around_action :switch_locale

  def index
    page_params = {
      path: "/education/teachers/toolbox/resources",
      locale: user_locale,
      url: request.url,
      query: request.query_parameters,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::Core::Pages::IndexPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing?

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
    page_params = {
      path: "/education/teachers/toolbox/resources/#{params[:slug]}",
      locale: user_locale,
      url: request.url,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::ContainerPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing?

    add_breadcrumb "Education", "/education"
    add_breadcrumb "Teachers", "/education/teachers"
    add_breadcrumb "Toolbox", "/education/teachers/toolbox"
    add_breadcrumb "Resources", "/education/teachers/toolbox/resources"
    add_breadcrumb page.title, "/education/teachers/toolbox/resources/#{params[:slug]}"

    react_render_params = {
      app_payload_generator: page.has_form? ? app_payload_generator : nil,
      payload: {
        contentfulRawJsonResponse: page.view_data,
        userLoggedIn: logged_in?,
        breadcrumbLinks: breadcrumbs,
        indexPath: "/education/teachers/toolbox/resources",
      },
      title: page.title,
      page_data: { **page.options },
    }.compact

    render_react_app(**react_render_params)
  end

  private

  def app_payload_generator
    lambda do
      {
        octocaptchaHost: GitHub.urls.octocaptcha_host_name,
        marketingFormsApiHost: GitHub.marketing_forms_api_host_url,
        marketingTargetedCountries: marketing_targeted_countries
      }
    end
  end

  def marketing_targeted_countries
    ::TradeControls::Countries.marketing_targeted_countries.map { |name, alpha, *_| { name: name, alpha: alpha } }
  end
end
