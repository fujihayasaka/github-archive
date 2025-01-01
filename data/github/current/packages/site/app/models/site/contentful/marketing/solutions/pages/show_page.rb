# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::ShowPage < Site::Contentful::Marketing::Solutions::Pages::BasePage
  def initialize(slug:)
    super(slug: slug)
  end

  private

  def page_type
    "show"
  end
end
