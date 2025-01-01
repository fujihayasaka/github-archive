# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::ShowPage < Site::Contentful::Marketing::Newsroom::Pages::BasePage
  def initialize(slug:)
    super(slug: "/newsroom/press-releases/#{slug}")
  end

  private

  def page_type
    "show"
  end
end
