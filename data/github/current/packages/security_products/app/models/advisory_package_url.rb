# typed: true
# frozen_string_literal: true

class AdvisoryPackageUrl

  ECOSYSTEM_PACKAGE_CACHE_KEY_PREFIX = "ecosystem_package_url"

  attr_reader :ecosystem, :package_name

  def initialize(ecosystem, package_name)
    @ecosystem = ecosystem&.downcase # Especially for RubyGems, we need to downcase the ecosystem name.
    @package_name = package_name
  end

  def get_url
    return unless ecosystem.present? && package_name.present?
    return unless supported_ecosystem?

    GitHub.cache.fetch(ecosystem_package_cache_key) do
      url = fetch_package_url
      GitHub::Telemetry::Logs.logger.debug { "storing '#{url}' to #{ecosystem_package_cache_key}" } if url.present?
      url
    end
  end

  def supported_ecosystem?
    AdvisoryDBToolkit::PackageUrlObtainer.supported_ecosystem?(ecosystem)
  end

  private

  def fetch_package_url
    AdvisoryDBToolkit::PackageUrlObtainer.get_url(ecosystem, package_name, faraday)
  rescue => e # rubocop:disable Lint/RescueException
    GitHub::Telemetry::Logs.logger.error { "Failed to fetch package URL for #{ecosystem}-#{package_name}: #{e.message}" }
    nil
  end

  def ecosystem_package_cache_key
    @ecosystem_package_cache_key ||= [ECOSYSTEM_PACKAGE_CACHE_KEY_PREFIX, Rails.env, ecosystem, package_name].join(":")
  end

  def faraday
    GitHub::FaradayClient::External.new do |c|
      c.adapter Faraday.default_adapter
    end
  end
end
