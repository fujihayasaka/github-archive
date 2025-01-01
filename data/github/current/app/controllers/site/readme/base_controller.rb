# typed: true
# frozen_string_literal: true

class Site::Readme::BaseController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index, :show]
  before_action :set_flash_if_nomination_submitted, only: [:index, :show]
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  YOUTUBE_HOST = "https://www.youtube.com"

  CSP_EXCEPTIONS = {
    frame_src: [YOUTUBE_HOST],
    img_src: [GitHub.contentful_readme_image_host_url, GitHub.contentful_readme_download_host_url],
    media_src: [GitHub.contentful_readme_asset_host_url, GitHub.contentful_readme_download_host_url]
  }

  layout "layouts/readme"

  javascript_bundle "marketing-readme"
  stylesheet_bundle "readme"

  private

  def readme_staff?
    user_feature_enabled?(:contentful_readme)
  end

  helper_method :readme_staff?

  def force_readme_cache_miss?
    return false unless readme_staff?

    params.has_key?(:force_cache)
  end

  helper_method :force_readme_cache_miss?

  def set_flash_if_nomination_submitted
    if params.has_key?(:submitted)
      flash[:notice] = "Thanks for your submission!"
    end
  end
end
