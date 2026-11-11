# typed: strict
# frozen_string_literal: true

class Site::Security::PublicMonitoringController < Site::Security::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
  only: [:show]

  before_action :check_public_monitoring_enabled
  before_action :add_csp_exceptions
  before_action :localized_alternative_links, only: :show
  before_action :hide_chrome, only: :show
  around_action :switch_locale, only: :show

  CSP_EXCEPTIONS = T.let(
    {
      img_src: [GitHub.contentful_marketing_image_host_url],
    }.freeze,
    T::Hash[Symbol, T::Array[String]],
  )

  stylesheet_bundle "landing-pages"

  class IndexPayload < ReactPayload::Base
    sig { params(contentful_raw_json_response: T.untyped).void }
    def initialize(contentful_raw_json_response:)
      @contentful_raw_json_response = contentful_raw_json_response
    end

    sig { override.returns(String) }
    def route_id
      "publicMonitoringRoute"
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      { contentfulRawJsonResponse: @contentful_raw_json_response }
    end
  end

  sig { void }
  def show
    options = {
      slug: request&.path,
      preview: fetch_contentful_preview?
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, **options) unless fetch_contentful_preview?
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(**options).view_data

    respond_with_react(
      app_name: "secret-scanning-public-monitoring-landing-page",
      title: "GitHub Advanced Security · Public Monitoring",
      payload: IndexPayload.new(
        contentful_raw_json_response: contentful_page_data[:contentful_raw_json_response],
      ),
    )
  end

  private

  sig { void }
  def hide_chrome
    @hide_header_content = T.let(true, T.nilable(T::Boolean))
    @marketing_page_theme = T.let("light", T.nilable(String))
    @marketing_footer_theme = T.let("light", T.nilable(String))
  end

  sig { void }
  def check_public_monitoring_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_public_monitoring_landing, current_user, default: false)
  end
end
