# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::OverviewPage < Site::Contentful::Marketing::Solutions::Pages::BasePage
  sig { void }
  def initialize
    super(slug: "/solutions")
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    template_schema = Site::Contentful::Marketing::Solutions::Schemas::OverviewPage.build
    page_schema = Site::Contentful::Swp::Schemas::Page.build

    page = data[:contentful_raw_json_response].dig("items", 0, "fields")

    template = (data[:contentful_raw_json_response].dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "solutionsTemplateOverview"
    end

    JSON::Validator.validate!(page_schema, page)
    JSON::Validator.validate!(template_schema, template["fields"] || {})
  end

  protected

  sig { override.returns(String) }
  def page_type
    "overview"
  end
end
