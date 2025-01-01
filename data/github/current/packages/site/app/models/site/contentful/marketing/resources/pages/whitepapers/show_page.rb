# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage < Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage
  def initialize(slug:)
    super(slug: "/resources/whitepapers/#{slug}")
  end

  private

  def page_type
    "show"
  end
end
