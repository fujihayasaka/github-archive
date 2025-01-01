# frozen_string_literal: true

class EPSSController < InboxController
  def show
    render AdvisoryReviews::EPSSComponent.new(ghsa_id: params[:ghsa_id]), layout: false
  end
end
