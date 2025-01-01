# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::CarouselCardComponent < ApplicationComponent

  def initialize(testimonial, active = false)
    @testimonial = testimonial
    @active = active
    @profile = testimonial[:profile]
  end

  def render?
    @testimonial.present?
    @profile.present?
  end
end
