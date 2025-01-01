# typed: true
# frozen_string_literal: true

class OpenGraph::Scanner::Result
  include GitHub::Memoizer

  attr_reader :error, :status

  sig do
    params(
      tags: T::Hash[String, String],
      status: T.nilable(Integer),
      error: T.nilable(T.any(Faraday::Error, Nokogiri::XML::SyntaxError))
    ).void
  end
  def initialize(tags: {}, status: nil, error: nil)
    @tags = tags
    @status = status
    @error = error
  end

  sig { returns(T::Boolean) }
  def success?
    error&.nil?
  end

  sig { returns(T::Boolean) }
  def ok?
    (200...300).include?(status)
  end

  sig { returns(T::Boolean) }
  def empty?
    title.empty? && description.empty?
  end

  sig { returns(String) }
  def title
    tags.fetch(:title, "")
  end

  sig { returns(String) }
  def description
    tags.fetch(:description, "")
  end

  sig { returns(T.nilable(String)) }
  memoize def image
    image_url = tags.fetch(:image, "")
    return if image_url.empty?

    uri = URI.parse(image_url)
    if "#{uri.scheme}://#{uri.host}" == GitHub.og_image_generator_base_url
      image_url
    else
      GitHub::HTML::CamoFilter.asset_proxy_url(image_url)
    end
  end

  sig { returns(String) }
  def site_name
    tags.fetch(:site_name, "")
  end

  sig { returns(String) }
  def url
    tags.fetch(:url, "")
  end

  sig { returns(String) }
  def image_width
    tags.fetch(:image_width, "")
  end

  sig { returns(String) }
  def image_height
    tags.fetch(:image_height, "")
  end

  private

  attr_reader :tags
end
