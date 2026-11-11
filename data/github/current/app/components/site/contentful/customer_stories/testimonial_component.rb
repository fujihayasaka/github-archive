# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::TestimonialComponent < ApplicationComponent
  def initialize(testimonial)
    @testimonial = testimonial
    @profile = testimonial.profile
    @encoded_tweet = ERB::Util.url_encode(testimonial.quote)
  end

  def render?
    @testimonial.present?
  end
end
