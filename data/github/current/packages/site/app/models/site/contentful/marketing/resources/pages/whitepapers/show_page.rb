# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage < Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage
  sig { params(slug: String).void }
  def initialize(slug:)
    super(slug: "/resources/whitepapers/#{slug}")
  end

  protected

  sig { override.returns(String) }
  def page_type
    "show"
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    page = data[:contentful_raw_json_response].dig("items", 0, "fields")

    template = (data[:contentful_raw_json_response].dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "templateWhitepaper"
    end
    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    JSON::Validator.validate!(Site::Contentful::Marketing::Resources::Pages::Whitepapers::Schemas::ShowPage.build, template["fields"] || {})
  end

end
