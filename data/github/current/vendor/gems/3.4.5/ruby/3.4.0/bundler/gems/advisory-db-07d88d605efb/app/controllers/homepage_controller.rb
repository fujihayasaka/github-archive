# frozen_string_literal: true

class HomepageController < InboxController
  def show
    cve_reviews = CVEReview
      .open
      .since_yesterday
    advisory_reviews = AdvisoryReview
      .curation_state_open
      .by_campaign(nil)
      .since_yesterday
      .preload(:feed_entries, :advisory, :cve_review)
      .paginate(page: params[:page])

    render locals: {
      cve_reviews: cve_reviews,
      advisory_reviews: advisory_reviews,
    }
  end
end
