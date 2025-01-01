# frozen_string_literal: true

class ReferencesCheck
  def self.should_run?(_review)
    true
  end

  CACHE_KEY_ROOT = "references_check"
  CACHE_TTL = 48.hours
  URL_LIMIT = 10

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    urls = if review.instance_of?(AdvisoryReview)
             review.advisory_payload["references"]
           else
             review.misc_references
           end

    if review.instance_of?(AdvisoryReview) && urls.blank?
      return CheckResult.new(
        status: "failed",
        title: "No references present",
        summary: "",
      )
    end

    if review.instance_of?(CVEReview)
      if review.confirm_reference.blank?
        return CheckResult.new(
          status: "failed",
          title: "No confirm reference present",
          summary: "",
        )
      end

      references_with_whitespace = []

      urls.each do |url|
        if /\s/.match?(url)
          references_with_whitespace << url
        end
      end

      if references_with_whitespace.any?
        return CheckResult.new(
          status: "failed",
          title: "URL contains whitespace",
          summary: "The URL(s) \"#{references_with_whitespace.join(", ")}\" contains whitespace",
        )
      end

      res, _cached = get_response(review.confirm_reference)
      unless res["success"]
        return CheckResult.new(
          status: "failed",
          title: "Couldn't fetch confirm reference",
          summary: "#{review.confirm_reference} returned a #{res["code"]}",
        )
      end
    end

    result_status = "passed"
    result_title = "references are OK"
    result_summary = ""

    new_urls = 0
    urls.each do |url|
      if new_urls == URL_LIMIT
        if result_status != "warning"
          result_status = "warning"
          result_title = "Not all URLs fetched"
        end
        result_summary += "Only fetched the first #{URL_LIMIT} URLs\n"

        break
      end

      response, cached = get_response(url)
      new_urls += 1 unless cached
      next if response["success"]

      result_status = "warning"
      result_title = "Couldn't fetch URL"
      result_summary += "#{url} returned a #{response["code"]}\n"
    end

    CheckResult.new(
      status: result_status,
      title: result_title,
      summary: result_summary,
    )
  end

  ERROR_CODES_TO_CACHE = [301, 302, 303, 304, 307, 308, 401, 403, 408].freeze

  # Checks the response of a URL, and caches the results
  #
  # Returns both an result object containing the success status of the response, and the response code
  # and whether the result was found in the cache
  private_class_method def self.get_response(url)
    cache_key = [CACHE_KEY_ROOT, Rails.env, url].join(":")

    cached_value = AdvisoryDB.redis.get(cache_key)
    ::GitHub::Telemetry::Logs.logger.debug { "found '#{cached_value}' at #{cache_key}" }
    return [JSON.parse(cached_value), true] if cached_value.present?

    begin
      response = connection.get(URI(url))
      value = { success: response.success?, code: response.status }.with_indifferent_access
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed
      ::GitHub::Telemetry::Logs.logger.info(
        "Timed out looking up reference URL",
        "url.full": url,
      )
      # When a response timesout set the status to 408, and cache results
      value = { success: false, code: 408 }.with_indifferent_access
    end

    # We don't want to cache all failures in case they're transient
    return [value, false] unless value[:success] || ERROR_CODES_TO_CACHE.include?(value[:code])

    ::GitHub::Telemetry::Logs.logger.debug { "storing '#{value}' to #{cache_key}" }
    AdvisoryDB.redis.set(cache_key, value.to_json, ex: CACHE_TTL.to_i)

    [value, false]
  end

  private_class_method def self.connection
    return @connection if defined?(@connection)

    @connection = Faraday.new do |conn|
      conn.request :instrumentation, name: "references_check.faraday"
      conn.options.timeout = 5
    end
  end
end
