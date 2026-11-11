# typed: true
# frozen_string_literal: true

class Site::ServicesController < Site::BaseController
  include SiteHelper

  before_action :add_csp_exceptions, only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index, :show, :terms_and_conditions]

  CSP_EXCEPTIONS = {
    form_action: %w( https://s88570519.t.eloqua.com/e/f2 ),
    media_src: [GitHub.asset_host_url, ExploreFeed::ProfessionalService::PROFESSIONAL_SERVICES_FEED_URL],
    connect_src: [GitHub.asset_host_url]
  }.freeze

  javascript_bundle "marketing-form-validator"
  stylesheet_bundle "marketing-services"

  def index
    render "site/services/index"
  end

  def show
    if service.present?
      render "site/services/show", locals: { service: service }
    else
      render_404
    end
  end

  def thanks # rubocop:todo GitHub/UseRestfulActions
    render "site/services/thanks"
  end

  def terms_and_conditions # rubocop:todo GitHub/UseRestfulActions
    render "site/services/terms_and_conditions"
  end

  private

  def service # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_service ||= ExploreFeed::ProfessionalService.find_by_parameterized_name(params[:id])
  end
end
