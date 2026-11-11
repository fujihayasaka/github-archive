# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Stafftools::Users::MeteredExportsController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  layout :billing_layout
  before_action :ensure_user_exists

  def index
    render "stafftools/users/metered_exports/index", locals: {
      metered_exports: this_user.metered_usage_exports.preload(:requester).order(created_at: :desc)
    }
  end

  def show
    export = this_user.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  def create
    ::Billing::MeteredReportExportJob.perform_later(current_user, this_user, params[:days].to_i)

    flash[:notice] = "We're preparing your report! We’ll attempt to send an email to #{current_user.email} when it’s ready, but the email may not work. Please refresh the page in a few minutes to see if the report has been generated."

    redirect_to stafftools_user_metered_exports_path(this_user)
  end
end
