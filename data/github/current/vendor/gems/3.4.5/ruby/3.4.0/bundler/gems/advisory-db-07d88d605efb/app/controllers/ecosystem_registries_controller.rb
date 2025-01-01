# frozen_string_literal: true

class EcosystemRegistriesController < InboxController
  rescue_from AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError, with: :render_error
  rescue_from URI::InvalidURIError, with: proc { render_response(status: 400, error: "Invalid Package") }

  CACHE_KEY_ROOT = "ecosystem_registries"
  CACHE_TTL = 24.hours

  def package_link
    ecosystem = params[:ecosystem]
    package_name = params[:package_name].strip

    return not_found unless ecosystem.present? && package_name.present?

    cache_key = cache_key(ecosystem, package_name)
    cached_value = AdvisoryDB.redis.get(cache_key)
    ::GitHub::Telemetry::Logs.logger.debug { "found '#{cached_value}' at #{cache_key}" }
    return render_response({ package_url: JSON.parse(cached_value)["value"] }) if cached_value.present?

    return unsupported_ecosystem unless AdvisoryDBToolkit::PackageUrlObtainer.supported_ecosystem?(ecosystem)

    package_url = AdvisoryDBToolkit::PackageUrlObtainer.get_url(ecosystem, package_name, Faraday.new)

    return not_found unless package_url

    ::GitHub::Telemetry::Logs.logger.debug { "storing '#{{ value: package_url }.to_json}' to #{cache_key}" }
    AdvisoryDB.redis.set(cache_key, { value: package_url }.to_json, ex: CACHE_TTL.to_i)

    render_response({ package_url: })
  end

  private

  def not_found
    render_response({ package_url: nil })
  end

  def render_error(error)
    ::GitHub::Telemetry::Logs.logger.error(
      "Error during ecosystem registry lookup",
      exception: error,
    )
    render_response(status: error.status, error: error.message)
  end

  def render_response(response)
    render json: response.reverse_merge(status: 200, error: nil)
  end

  def unsupported_ecosystem
    render_response(error: "Unsupported ecosystem")
  end

  def cache_key(ecosystem, package_name)
    [CACHE_KEY_ROOT, Rails.env, ecosystem, package_name].join(":")
  end
end
