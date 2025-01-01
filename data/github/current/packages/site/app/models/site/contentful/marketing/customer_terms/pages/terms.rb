# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::CustomerTerms::Pages::Terms
  def view_data
    fetch_data_from_contentful
  end

  def fetch_data_from_contentful
    Site::Contentful::Marketing::Page.find("customer-terms")
  end
end
