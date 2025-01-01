# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::OverviewPage < Site::Contentful::Marketing::Solutions::Pages::BasePage
  def initialize
    super(slug: "/solutions")
  end

  private

  def page_type
    "overview"
  end
end
