# frozen_string_literal: true

module PaginationTestHelpers
  def paged_url_rel_links(url, page, max)
    url += "?" unless url.include?("?")

    links = [
      "<#{url}page=1>; rel=\"first\"",
      "<#{url}page=#{max}>; rel=\"last\"",
    ]

    links << "<#{url}page=#{page - 1}>; rel=\"prev\"" if page > 1
    links << "<#{url}page=#{page + 1}>; rel=\"next\"" if page < max

    links.join(", ")
  end
end
