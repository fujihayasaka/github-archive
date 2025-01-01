# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::HomePage < Site::Contentful::Marketing::Newsroom::Pages::BasePage
  def initialize
    @slug = "/newsroom"
  end

  private

  def page_type
    "home"
  end
end
