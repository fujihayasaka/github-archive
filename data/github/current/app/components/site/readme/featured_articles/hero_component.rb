# typed: true
# frozen_string_literal: true

class Site::Readme::FeaturedArticles::HeroComponent < ApplicationComponent
  include Site::ReadmeHelper
  include SvgHelper
  include UrlHelper

  def initialize(story:)
    @story = story
  end

  def show_author_and_date
    name = fullname(@story[:author])
    date = Time.rfc2822(@story[:publication_date_rfc2822]).strftime("%B %e, %Y")

    [name, date].compact.join(" // ")
  end
end
