# typed: strict
# frozen_string_literal: true

class Site::Resources::PagesController < Site::Resources::BaseController
  include Site::BreadcrumbDependency
  around_action :switch_locale, only: [:show]
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = T.let({
    connect_src: [GitHub.marketing_forms_api_host_url],
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze, T::Hash[Symbol, T::Array[String]])

  before_action :load_resources_stylesheet

  sig { void }
  def show
    page_params = {
      path: resource_path,
      locale: user_locale,
      url: request.url,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::ContainerPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page)

    add_breadcrumb resource_label, type_path
    add_breadcrumb page.title, resource_path

    react_render_params = {
      app_payload_generator: app_payload_generator,
      payload: {
        contentfulRawJsonResponse: page.view_data,
        userLoggedIn: logged_in?,
        breadcrumbLinks: breadcrumbs,
        indexPath: type_path,
      },
      title: page.title,
      page_data: { **page.options },
    }.compact

    render_react_app(**react_render_params)
  end

  private

  sig { returns(String) }
  def type_path
    resources_type_path(params[:resource_type])
  end

  sig { returns(String) }
  def resource_path
    resources_page_path(params[:resource_type], params[:resource])
  end

  sig { returns(String) }
  def resource_label
    return "" if params[:resource_type].blank?
    params[:resource_type].titleize
  end

  sig { params(page: Site::Contentful::Marketing::ContainerPage).returns(T::Boolean) }
  def hidden?(page)
    return false if page.feature_flag.blank?

    !FeatureFlag.vexi.enabled?(page.feature_flag, current_user, default: false)
  end

  sig { returns(Proc) }
  def app_payload_generator
    lambda do
      {
        octocaptchaHost: GitHub.urls.octocaptcha_host_name,
        marketingFormsApiHost: GitHub.marketing_forms_api_host_url,
        marketingTargetedCountries: marketing_targeted_countries
      }
    end
  end

  sig { void }
  def load_resources_stylesheet
    if FeatureFlag.vexi.enabled?("primer_brand_next", current_user, default: false)
      self.stylesheet_bundles.add(:"resources-next")
    else
      self.stylesheet_bundles.add(:"resources")
    end
  end
end
