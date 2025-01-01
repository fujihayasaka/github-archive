# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage < Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage
  sig { params(slug: String, locale: T.nilable(Symbol)).void }
  def initialize(slug:, locale: :en)
    super(slug: "/resources/whitepapers/#{slug}", locale: locale)
  end

  protected

  sig { override.returns(String) }
  def page_type
    "show"
  end

  sig { override.params(new_data: JsonLikeType).void }
  def validate!(new_data)
    page = new_data[:contentful_raw_json_response].dig("items", 0, "fields")

    template = (new_data[:contentful_raw_json_response].dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "templateWhitepaper"
    end

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    JSON::Validator.validate!(Site::Contentful::Marketing::Resources::Pages::Whitepapers::Schemas::ShowPage.build, template["fields"] || {})
  end

end
