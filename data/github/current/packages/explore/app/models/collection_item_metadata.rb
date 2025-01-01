# typed: true
# frozen_string_literal: true

class CollectionItemMetadata
  def self.build_from_url(url)
    parsed_url = URI.parse(url)
    connection = Faraday.new(url: parsed_url) do |faraday|
      faraday.adapter Faraday.default_adapter
    end

    response = connection.get do |request|
      request.options.timeout = 1.second
      request.options.open_timeout = 5.seconds
    end

    doc = Nokogiri::HTML(response.body)
    title = doc.title
    description_meta = doc.at("meta[name='description']") || doc.at("meta[property='og:description']")
    description = description_meta["content"]

    [title, description]
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError, URI::InvalidURIError, URI::BadURIError
    [nil, nil]
  end
end
