# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::LandingPages::ContentTypes::ContainerPage < Contentful::Entry
  include Site::Contentful::Marketing::Client

  sig { params(slug: String, locale: String, preview: T::Boolean).returns(T.untyped) }
  def self.get_raw_json_for(slug:, locale: "en-US", preview: false)
    params = {
      content_type: "containerPage",
      "fields.path": slug,
      include: 10,
      locale: locale,
    }

    contentful_raw_request(params, preview: preview)
  end
end
