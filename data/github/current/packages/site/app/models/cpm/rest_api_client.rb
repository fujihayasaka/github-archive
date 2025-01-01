# typed: true
# frozen_string_literal: true

module Cpm
  class RestApiClient

    SERVER_ERROR_MSG = "Something went wrong. Please try again later."
    CLIENT_DOUBLE_OPTIN_ERROR_MSG = "Something went wrong. The signup request you are attempting to confirm cannot be located."
    CLIENT_ERROR_MSG = "Something went wrong. Please request a new link to manage your email preferences."

    PUBLIC_ENDPOINT_TIMEOUT_SECONDS = 0.75
    DEFAULT_TIMEOUT_SECONDS = 2

    def initialize(api_client = Cpm::HttpClient.new)
      @api_client = api_client
    end

    # Check email contactability and generate unsubscribe link
    sig { params(emails: T::Array[String], topic_id: String, campaign_id: String).returns(Hash) }
    def check_email_contactability(emails, topic_id, campaign_id)
      if campaign_id.length > 40
        return { has_error: true, message: "Campaign ID exceeds maximum character count of 40." }
      end

      if emails.length > 30
        return { has_error: true, message: "Too many contacts in request. Maximum allowed is 30." }
      end

      body = {
        campaignId: campaign_id,
        contactPoints: emails,
        targetedTopicId: topic_id,
        unsubscribeUrlRequired: true
      }

      start = GitHub::Dogstats.monotonic_time
      cpm_endpoint = "EmailContactabilities"
      response = @api_client.request(
        method: :post,
        slug: cpm_endpoint,
        body: body,
        timeout: PUBLIC_ENDPOINT_TIMEOUT_SECONDS
      )

      report_timing_dd(start, status: response.status, method: "check_email_contactability", cpm_endpoint: cpm_endpoint)

      if response.status == 200
        {
          has_error: false,
          contacts: response.body[:contacts]
        }
      else
        { has_error: true, message: "Failed to check email contactability." }
      end
    rescue Faraday::TimeoutError, Errno::ETIMEDOUT, Timeout::Error
      report_timing_dd(start, status: "timeout", errored: true, method: "check_email_contactability", cpm_endpoint: cpm_endpoint)
      { has_error: true, timeout: true }
    rescue Faraday::Error => err
      status = err.response&.[](:status) || "unknown"
      report_timing_dd(start, status: status, errored: true, method: "check_email_contactability", cpm_endpoint: cpm_endpoint)

      message = err.is_a?(Faraday::ClientError) ? CLIENT_ERROR_MSG : SERVER_ERROR_MSG
      { has_error: true, message: message }
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

    sig { params(params: ActionController::Parameters).returns(Hash) }
    def double_opt_in(params)
      permitted_params = map_url_params_to_request_schema(params)

      unless permitted_params[:requestId].present?
        permitted_params[:communicationId] ||= permitted_params[:topicId]
      end
      permitted_params[:partnerId] ||= "GitHub"

      cpm_endpoint = "ContactPoints/DoubleOptinVerification"

      start = GitHub::Dogstats.monotonic_time
      response = @api_client.request(
        method: :patch,
        slug: cpm_endpoint,
        body: permitted_params,
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
      message = if err.is_a?(Faraday::ClientError)
        CLIENT_DOUBLE_OPTIN_ERROR_MSG
      else
        SERVER_ERROR_MSG
      end
      { has_error: true, message: message }
    end

    private

    def map_url_params_to_request_schema(params)
      key_values = {
        "CTID" => :contactType,
        "ECID" => :contactValue,
        "K"    => :keyId,
        "D"    => :createdDate,
        "PID"  => :partnerId,
        "TID"  => :topicId,
        "RID"  => :requestId,
        "MK"   => :culture
      }
      transform_params(params, key_values)
    end

    def parse_url_params(params)
      key_values = {
        "CTID" => "ContactType",
        "ECID" => "ContactValue",
        "K"    => "KeyId",
        "D"    => "CreatedDate",
        "PID"  => "PartnerID",
        "TID"  => "TopicId",
        "RID"  => "RequestId",
        "MK"   => "Culture"
      }
      transform_params(params, key_values)
    end

    def transform_params(params, mapping)
      updated_params = {}
      params.each do |key, value|
        new_key = mapping[key]
        updated_params[new_key] = value if new_key.present?
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
