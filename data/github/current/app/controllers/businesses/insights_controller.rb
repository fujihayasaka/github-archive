# typed: true
# frozen_string_literal: true

class Businesses::InsightsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :insights_available_required
  before_action :try_redirect_to_insights, only: [:index]
  before_action :validate_insights_url, only: [:update_base_url]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:settings]

  def index
    render "businesses/insights/index"
  end

  def settings # rubocop:todo GitHub/UseRestfulActions
    render "businesses/settings/insights"
  end

  def update_base_url # rubocop:todo GitHub/UseRestfulActions
    GitHub.insights_url = params[:insights_url]
    flash[:notice] = "You have set the URL for your GitHub Insights instance successfully."
    redirect_to settings_enterprise_insights_path(this_business)
  end

  private

  def insights_available_required
    render_404 unless GitHub.insights_available?
  end

  def try_redirect_to_insights
    return unless GitHub.insights_url
    redirect_to GitHub.insights_url
  end

  def validate_insights_url
    valid_url = begin
      Addressable::URI.parse(params[:insights_url])&.host&.present?
    rescue Addressable::URI::InvalidURIError
      false
    end

    return if valid_url

    flash[:error] = "Provided url was not valid"
    redirect_to settings_enterprise_insights_path(this_business)
  end
end
