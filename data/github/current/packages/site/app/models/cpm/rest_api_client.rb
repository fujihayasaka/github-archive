# typed: true
# frozen_string_literal: true

module Cpm
  class RestApiClient
    extend T::Sig

    SERVER_ERROR_MSG = "Something went wrong. Please try again later."
    CLIENT_ERROR_MSG = "Something went wrong. Please request a new link to manage your email preferences."

    PUBLIC_ENDPOINT_TIMEOUT_SECONDS = 0.75
    DEFAULT_TIMEOUT_SECONDS = 2

    def initialize(api_client = Cpm::HttpClient.new)
      @api_client = api_client
    end

    # Update email subscription preferences
    sig { params(body: Hash, unsubscribe_ids: T::Array[T.nilable(String)]).returns(Hash) }
    def unsubscribe(body, unsubscribe_ids)
      body[:topics] = body[:topics].select { |topic| unsubscribe_ids.include?(topic[:id]) }
      body[:topics] = body[:topics].map do |topic|
        topic = set_source_set_date(topic)
        topic[:canContact] = false
        topic
      end

      if body[:communicationId].nil?
        body[:lastModifiedBy] = "GitHub - Email Preferences Center"
      else
        body[:lastModifiedBy] = "GitHub - #{body[:communicationId]}"
      end

      start = GitHub::Dogstats.monotonic_time
      # send to the TargetedUnsubscribe endpoint
      cpm_endpoint = "ContactPoints/TargetedUnsubscribe"
      response = @api_client.request(
          method: :patch,
          slug: cpm_endpoint,
          body: body,
          timeout: PUBLIC_ENDPOINT_TIMEOUT_SECONDS
      )

      report_timing_dd(start, status: response.status, method: "unsubscribe", cpm_endpoint: cpm_endpoint)
      { has_error: false }
    rescue Faraday::TimeoutError, Errno::ETIMEDOUT, Timeout::Error
      report_timing_dd(start, status: "timeout", errored: true, method: "unsubscribe", cpm_endpoint: cpm_endpoint)
      { has_error: true, timeout: true }
    rescue Faraday::Error => err
      status = err.response&.[](:status) || "unknown"
      report_timing_dd(start, status: status, errored: true, method: "unsubscribe", cpm_endpoint: cpm_endpoint)

      message = err.is_a?(Faraday::ClientError) ? CLIENT_ERROR_MSG : SERVER_ERROR_MSG
      { has_error: true, message: message }
    end

    sig { params(email: String).returns(Hash) }
    def get_authentication_url(email)
      cpm_endpoint = "UnsubscribeAllLink"

      start = GitHub::Dogstats.monotonic_time
      response = @api_client.request(
        method: :post,
        slug: cpm_endpoint,
        body: {
          contacts: [{ contactType: "email", contactValue: email }],
        },
        timeout: DEFAULT_TIMEOUT_SECONDS
      )
      report_timing_dd(start, status: response.status, method: "get_authentication_url", cpm_endpoint: cpm_endpoint)

      unsubscribe_url = response.body[:contacts].first[:unsubscribeAllUrl]
      { url: unsubscribe_url }
    rescue Faraday::TimeoutError, Errno::ETIMEDOUT, Timeout::Error
      report_timing_dd(start, status: "timeout", errored: true, method: "get_authentication_url", cpm_endpoint: cpm_endpoint)
      { has_error: true, timeout: true }
    rescue Faraday::Error => err
      status = err.response&.[](:status) || "unknown"
      report_timing_dd(start, status: status, errored: true, method: "get_authentication_url", cpm_endpoint: cpm_endpoint)
      message = err.is_a?(Faraday::ClientError) ? CLIENT_ERROR_MSG : SERVER_ERROR_MSG
      { has_error: true, message: message }
    end

    # Get email + topics from the CPM generated link
    sig { params(params: ActionController::Parameters).returns(Hash) }
    def get_topic_settings_from_cpm_link(params)
      updated_params = parse_url_params(params)
      cpm_endpoint = "ContactPoints/TopicSettings"

      start = GitHub::Dogstats.monotonic_time
      response = @api_client.request(
        method: :get,
        slug: cpm_endpoint,
        params: { **updated_params, TopicBrand: "GitHub", TopicId: "00000000-0000-0000-0000-000000000006" },
        timeout: DEFAULT_TIMEOUT_SECONDS
      )
      report_timing_dd(start, status: response.status, method: "get_topic_settings_from_cpm_link", cpm_endpoint: cpm_endpoint)

      response.body[:topics] = response.body[:topics].select { |topic| topic[:canContact] }
      { email: response.body[:decryptedContactValue], data: response.body }
    rescue Faraday::TimeoutError, Errno::ETIMEDOUT, Timeout::Error
      report_timing_dd(start, errored: true, status: "timeout", method: "get_topic_settings_from_cpm_link", cpm_endpoint: cpm_endpoint)
      { has_error: true, timeout: true }
    rescue Faraday::Error => err
      status = err.response&.[](:status) || "unknown"
      report_timing_dd(start, errored: true, status: status, method: "get_topic_settings_from_cpm_link", cpm_endpoint: cpm_endpoint)

      message = err.is_a?(Faraday::ClientError) ? CLIENT_ERROR_MSG : SERVER_ERROR_MSG
      { has_error: true, cpm_resp: err.response, message: message, new_link_required: err.is_a?(Faraday::ClientError) }
    end

    sig { params(body: Hash, topic_id: String).returns(Hash) }
    def double_opt_in(body, topic_id)
      body[:topicId] = topic_id
      body[:partnerId] ||= "GitHub"
      body[:communicationId] ||= topic_id
      body[:topics] = body[:topics].select { |topic| topic[:id] == topic_id }

      cpm_endpoint = "ContactPoints/DoubleOptinVerification"

      start = GitHub::Dogstats.monotonic_time
      response = @api_client.request(
        method: :patch,
        slug: cpm_endpoint,
        body: body,
        timeout: PUBLIC_ENDPOINT_TIMEOUT_SECONDS
      )

      report_timing_dd(start, status: response.status, method: "double_opt_in", cpm_endpoint: cpm_endpoint)
      response.body
    rescue Faraday::TimeoutError, Errno::ETIMEDOUT, Timeout::Error
      report_timing_dd(start, errored: true, status: "timeout", method: "double_opt_in", cpm_endpoint: cpm_endpoint)
      { has_error: true, timeout: true }
    rescue Faraday::Error => err
      status = err.response&.[](:status) || "unknown"
      report_timing_dd(start, errored: true, status: status, method: "double_opt_in", cpm_endpoint: cpm_endpoint)
      message = err.is_a?(Faraday::ClientError) ? CLIENT_ERROR_MSG : SERVER_ERROR_MSG
      { has_error: true, message: message }
    end

    private

    def parse_url_params(params)
      updated_params = {}
      key_values = {
        "CTID" => "ContactType",
        "ECID" => "ContactValue",
        "K" => "KeyId",
        "D" => "CreatedDate",
        "PID" => "PartnerID",
        "TID" => "TopicId",
        "MK" => "Culture"
      }

      params.each do |key, value|
        full_key = key_values[key]
        updated_params[full_key] = value if full_key.present?
      end
      updated_params
    end

    def set_source_set_date(topic)
      date = DateTime.now
      date = date.new_offset(0)
      source_set_date = date.strftime("%d-%b-%Y %H:%M:%S %Z")
      { **topic, lastSourceSetDate: source_set_date }
    end

    def report_timing_dd(start, errored: false, method:, cpm_endpoint:, status:)
      GitHub.dogstats.distribution_timing_since("email_preferences_center.cpm_client", start, tags: [
        "status:#{status}",
        "errored:#{errored}",
        "method:#{method}",
        "cpm_endpoint:#{cpm_endpoint}"
      ])
    end
  end
end
