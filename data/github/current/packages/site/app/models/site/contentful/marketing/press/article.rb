# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Press::Article < Site::Contentful::Entry
  include Site::Contentful::Marketing::Client

  def self.content_type
    "entry_press_article"
  end

  def self.where(limit:, offset: 0)
    params = {
      content_type: content_type,
      "order": "-fields.date",
      limit: limit,
      skip: offset
    }.compact

    contentful_request(params)
  end

  def feed_json
    {
      active: true,
      featured: false,
      date: date,
      formatted_date: date&.strftime("%b %-d, %Y"),
      publication: publication,
      article_url: url,
      article_title: title
    }
  end
end
