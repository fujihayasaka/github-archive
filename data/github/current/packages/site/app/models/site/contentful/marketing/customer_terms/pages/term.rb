# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::CustomerTerms::Pages::Term
  def initialize(id: nil)
    @id = id
  end

  def view_data
    fetch_data_from_contentful
  end

  def fetch_data_from_contentful
    return if !@id.present?
    Site::Contentful::Marketing::Document.find("/customer-terms/#{@id}")
  end
end
