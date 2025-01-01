# typed: true
# frozen_string_literal: true

class Orgs::Sponsorings::MetadataController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:show]

  YEAR_OF_FIRST_INVOICED_PAYMENT = 2021

  before_action :ensure_user_can_access_insights
  before_action :require_xhr, only: :show

  def show
    metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: payments)

    respond_to do |format|
      format.json do
        render json: {
          series: {
            columns: metadata.column_types,
            rows: metadata.monthly_payments_in_dollars
          },
          aggregate: {
            monthly: metadata.aggregate_monthly_payments_in_dollars,
            yearly: metadata.aggregate_yearly_payments_in_dollars
          },
          year: target_year
        }
      end
    end
  end

  private

  def payments
    Sponsors::InvoicedSponsorshipLineItem.for_org(this_organization, time_range: beginning_of_year..end_of_year)
  end

  def beginning_of_year
    Date.new(target_year).in_time_zone.beginning_of_year
  end

  def end_of_year
    Date.new(target_year).in_time_zone.end_of_year
  end

  def target_year
    return now.year unless year_param_exists_and_is_valid?
    year_param.to_i
  end

  memoize def now
    Time.current
  end

  def year_param_exists_and_is_valid?
    return false unless year_param.present?
    year_is_not_in_the_future? && year_is_after_start_of_sponsors?
  end

  def year_is_not_in_the_future?
    year_param.to_i <= now.year
  end

  def year_is_after_start_of_sponsors?
    year_param.to_i >= YEAR_OF_FIRST_INVOICED_PAYMENT
  end

  def year_param
    params[:year]
  end

  memoize def sponsors_plan_subscription_id
    this_organization.sponsors_plan_subscription_id
  end

  def ensure_user_can_access_insights
    render_404 unless this_organization.sponsors_insights_accessible_by?(current_user)
  end
end
