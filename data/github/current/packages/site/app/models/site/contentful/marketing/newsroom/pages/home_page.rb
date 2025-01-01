# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::HomePage < Site::Contentful::Marketing::Newsroom::Pages::BasePage
  sig { void }
  def initialize
    @slug = "/newsroom"
  end

  protected

  sig { override.returns(T.untyped) }
  def page_template
    Site::Contentful::Marketing::Newsroom::Schemas::HomePage.build
  end

  sig { override.returns(String) }
  def page_type
    "home"
  end
end
