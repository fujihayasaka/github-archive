# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Asset < Contentful::Asset
  def absolute_url(options = {})
    return url if url.start_with?("http")

    "https:#{url}"
  end

  def to_json
    {
      title: title,
      description: description,
      url: url,
      absolute_url: absolute_url,
    }.compact
  end
end
