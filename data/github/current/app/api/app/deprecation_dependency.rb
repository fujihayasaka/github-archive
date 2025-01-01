# typed: true
# frozen_string_literal: true

# Functionality related to deprecating and sunsetting an API resource

module Api::App::DeprecationDependency
  # Deprecates an API endpoint using the Sunset Header as well
  # as approriate Link relations.
  #
  # sunset_date      - The date at which the endpoint may stop responding.
  # info_url         - An absolute URL to an HTML,
  #                    human readable description of the deprecation
  # alternate_path_url   - The URL to an alternative or new endpoint
  #
  # Example:
  #
  # Deprecation: Sun, 11 Nov 2018 23:59:59 GMT
  #
  # Sunset: Wed, 11 Nov 2020 23:59:59 GMT
  #
  # Link: <https://developer.github.com/blog-post-on-deprecation>; rel="deprecation"; type="text/html",
  #       <https://api.github.com/alternative/endpoint>; rel="alternate"
  #
  def deprecated(deprecation_date:, sunset_date:, info_url:, alternate_path_url: nil)
    @deprecated = {
      deprecation_date: deprecation_date,
      sunset_date: sunset_date,
      info_url: info_url,
      alternate_path_url: alternate_path_url,
    }
  end
end
