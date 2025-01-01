# typed: true
# frozen_string_literal: true

module CollectionsHelper
  CONTAINS_MARKDOWN_URL_REGEX = /\S*(\[(\S*)\]\((\S*)\)\.*)/
  HTTP_SCHEMES = %w(http https)
  SCHEME_AND_DOMAIN_PATH_DELIMITER = "://"

  def with_plain_text_links(short_description)
    match_data = short_description.scan(CONTAINS_MARKDOWN_URL_REGEX)

    if match_data.present?
      replacements = match_data.each_with_object({}) do |match_datum, replacement_data|
        markdown_link = match_datum[0]
        link_title = match_datum[1]
        url = match_datum[2]

        replacement_data[markdown_link] = plain_text_link(link_title, url)
      end

      short_description.split(" ").each_with_object([]) do |word, new_description|
        new_description << (replacements[word] || word)
      end.join(" ")
    else
      short_description
    end
  end

  private

  def plain_text_link(link_title, url)
    if http_link?(url) && these_are_the_same?(link_title, url)
      url
    else
      "#{link_title}: #{url}"
    end
  end

  def http_link?(url)
    url_scheme = URI.parse(url).scheme

    HTTP_SCHEMES.include?(url_scheme)
  end

  def these_are_the_same?(link_title, url)
    domain_and_path_only = url.split(SCHEME_AND_DOMAIN_PATH_DELIMITER)[1]

    domain_and_path_only == link_title
  end
end
