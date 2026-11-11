# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::FraudReviewsController < Stafftools::SponsorsController
  skip_before_action :sponsors_listing_required
  before_action :this_review_required, only: [:update]

  layout "application"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 100
  DEFAULT_STATE = "pending".freeze
  STATE_OPTIONS = ["all"] + SponsorsFraudReview.states.keys

  def index
    render "stafftools/sponsors/fraud_reviews/index", locals: {
      reviews: reviews,
      state: params[:state] || DEFAULT_STATE,
    }
  end

  def update
    success = case sanitized_state
    when :resolved
      this_review.resolve(actor: current_user)
    when :flagged
      this_review.flag(actor: current_user)
    when :pending
      this_review.revert_to_pending(actor: current_user)
    end

    if success
      flash[:notice] = "Marked as #{sanitized_state}."
    else
      flash[:error] = "Couldn't update review: #{this_review.errors.full_messages.to_sentence}"
    end

    redirect_to stafftools_sponsors_member_path(sponsorable)
  end

  private

  memoize def this_review
    SponsorsFraudReview.find_by(id: params[:id])
  end

  def this_review_required
    render_404 unless this_review.present?
  end

  delegate :sponsors_listing, to: :this_review
  delegate :sponsorable, to: :sponsors_listing

  memoize def reviews
    SponsorsFraudReview
      .filter_by_state(sanitized_state)
      .filter_by_sponsorable_login(params[:handle])
      .includes(:reviewer, sponsors_listing: :sponsorable)
      .ordered_by(params[:order])
      .paginate(page: current_page, per_page: PER_PAGE)
  end

  def sanitized_state
    if SponsorsFraudReview.states.keys.include?(params[:state])
      params[:state].to_sym
    elsif params[:state].blank?
      DEFAULT_STATE.to_sym
    end
  end
end
