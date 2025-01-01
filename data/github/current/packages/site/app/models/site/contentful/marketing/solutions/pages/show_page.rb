# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::ShowPage < Site::Contentful::Marketing::Solutions::Pages::BasePage
  sig { params(slug: String).void }
  def initialize(slug:)
    super(slug: slug)
  end

  sig { override.params(new_data: JsonLikeType).void }
  def validate!(new_data)
    template_schema = Site::Contentful::Marketing::Solutions::Schemas::ShowPage.build
    page_schema = Site::Contentful::Swp::Schemas::Page.build

    page = new_data[:contentful_raw_json_response].dig("items", 0, "fields")

    template = (new_data[:contentful_raw_json_response].dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "solutionsTemplateDetail" ||
      entry.dig("sys", "contentType", "sys", "id") == "templateFlex"
    end

    JSON::Validator.validate!(page_schema, page)

    return if template&.dig("sys", "contentType", "sys", "id") == "templateFlex"

    JSON::Validator.validate!(template_schema, template["fields"] || {})
  end

  protected

  sig { override.returns(String) }
  def page_type
    "show"
  end
end
