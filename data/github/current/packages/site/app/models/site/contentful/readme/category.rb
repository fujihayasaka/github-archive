# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Readme::Category < Site::Contentful::Entry
  include Site::Contentful::Readme::Client

  def self.content_type
    "category"
  end
end
