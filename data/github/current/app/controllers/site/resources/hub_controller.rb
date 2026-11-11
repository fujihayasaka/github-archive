# typed: strict
# frozen_string_literal: true

class Site::Resources::HubController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:show]
  depends_on_clusters ApplicationRecord::Mysql5, only: [:show], optional: true

  before_action :add_csp_exceptions, only: [:show]
  before_action :allow_initial_cookie_consent, only: [:show], if: :tracking_allowed?
  before_action :enable_microsoft_analytics, only: [:show], if: :tracking_allowed?
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show], if: :tracking_allowed?
  before_action :enable_fullstory, only: [:show]
  before_action :add_fullstory_csp_exceptions, only: [:show]

  CSP_EXCEPTIONS = T.let({
    connect_src: [GitHub.marketing_forms_api_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze, T::Hash[Symbol, T::Array[String]])

  before_action :load_landing_pages_stylesheet

  sig { void }
  def show
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled?(:contentful_lp_resources, current_user, default: false)

    redirect_to "https://resources.github.com/", status: 301
  end

  private

  sig { returns(T::Boolean) }
  def tracking_allowed?
    true
  end
end
