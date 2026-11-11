# typed: true
# frozen_string_literal: true

class Site::PricingController < Site::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions
  before_action :add_csp_exceptions, only: [:index], if: :use_contentful_pricing_page?
  before_action :load_pricing_bundles, only: [:index], unless: :use_contentful_pricing_page?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    only: [:index]

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url, GitHub.contentful_marketing_video_host_url],
  }.freeze

  stylesheet_bundle "landing-pages", if: :use_contentful_pricing_page?

  def index
    if use_contentful_pricing_page?
      render_contentful_pricing_page
    else
      render "site/pricing/index"
    end
  end

  private

  def use_contentful_pricing_page?
    FeatureFlag.vexi.enabled?(:site_pricing_brand_refactor, current_user, default: false)
  end

  def load_pricing_bundles
    self.javascript_bundles.add(:pricing)
    self.stylesheet_bundles.add(:pricing)
  end

  def render_contentful_pricing_page
    page_data = fetch_contentful_page_data

    return render_404 if page_data.blank? || landing_page_hidden?(page_data)

    render_react_landing_page(page_data: page_data)
  end
end
