# frozen_string_literal: true

module AdvisoryDBToolkit::Ecosystems
  module Packagist
    extend self
    # https://packagist.org/apidoc
    METADATA_ENDPOINT = "https://repo.packagist.org/p2/"
    PACKAGE_PAGE_ENDPOINT = "https://packagist.org/packages/"

    # https://packagist.org/apidoc#get-package-data
    def get_package_metadata(package_name)
      return nil unless package_name

      url = SafeUrl.build(METADATA_ENDPOINT, "#{package_name}.json")
      response = AdvisoryDBToolkit::PackageUrlObtainer.http_client.get(url)
      case response.status
      when 200
        JSON.parse response.body
      when 404
        nil
      else
        raise AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError.new("Packagist API error", response:)
      end
    end

    def get_package_url(package_name)
      return nil unless package_name

      metadata = get_package_metadata(package_name)
      return nil unless metadata

      SafeUrl.build(PACKAGE_PAGE_ENDPOINT, package_name).to_s
    end
  end
end
