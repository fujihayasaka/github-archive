# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::TestimonialsCarouselComponent < ApplicationComponent
  def initialize(testimonials)
    @testimonials = testimonials
  end

  def render?
    @testimonials.present?
  end
end
