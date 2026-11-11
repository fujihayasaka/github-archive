# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::ShowPage < Site::Contentful::Marketing::Newsroom::Pages::BasePage
  sig { params(slug: String).void }
  def initialize(slug:)
    super(slug: "/newsroom/press-releases/#{slug}")
  end

  protected

  sig { override.returns(T.untyped) }
  def page_template
    Site::Contentful::Marketing::Newsroom::Schemas::ShowPage.build
  end

  sig { override.returns(String) }
  def page_type
    "show"
  end
end
