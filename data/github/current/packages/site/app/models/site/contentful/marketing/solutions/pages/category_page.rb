# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::CategoryPage < Site::Contentful::Marketing::Solutions::Pages::BasePage
  def initialize(slug:)
    super(slug: "/solutions/#{slug}")
  end

  private

  def page_type
    "category"
  end
end
