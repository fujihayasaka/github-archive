# typed: true
# frozen_string_literal: true

class Businesses::OverviewReadmeComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  memoize def readme_editable?
    business_owner?
  end

  memoize def render_feedback_link_url?
    !GitHub.enterprise?
  end

  memoize def feedback_link_url
    if business_owner?
      "https://survey3.medallia.com/?ligHiQ-o1SSoAXU1lSsJCI"
    else
      "https://survey3.medallia.com/?rgRPu3-qhH0W0nvxLsMbZg"
    end
  end

  memoize def business_owner?
    business.owner?(current_user)
  end
end
