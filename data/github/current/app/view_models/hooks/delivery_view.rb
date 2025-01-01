# typed: true
# frozen_string_literal: true

module Hooks
  class DeliveryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    MAX_DELIVERY_CONTENT_SIZE = 600.kilobytes

    attr_reader :hook, :delivery

    delegate :hook_status, :status_code, :hook_response, :delivery_guid, :payload, :payload_empty?, :duration, :request_headers, :response_headers, :response_body, :redelivery?, :url, to: :delivery

    def activity_title
      if delivery.event
        title = "#{delivery.event}"
        if delivery.action
          title = "#{title}.#{delivery.action}"
        end
        title
      else
        nil
      end
    end

    def delivered_at
      if time = delivery.delivered_at
        time.in_time_zone(Time.zone)
      end
    end

    def delivery_id
      delivery.id
    end

    def response_status
      delivery.status_code
    end

    def repository
      hook.installation_target if hook.repo_hook?
    end

    def duration_in_seconds
      helpers.pluralize duration, "second"
    end

    def status_message
      case delivery.hook_status_label
      when :active
        "Success"
      when :unused
        "Unknown"
      when :hookshot_error
        "An Exception Occurred"
      else
        delivery.hook_response
      end
    end

    def status_class
      Hookshot::Delivery.status_class delivery.hook_status_label
    end

    def request_headers_html(*_)
      delivery_headers request_headers
    end

    def response_headers_html(*_)
      delivery_headers response_headers
    end

    def has_response?
      !response_headers.nil? && !response_headers.empty?
    end

    def highlighted_delivery_payload
      if payload_empty?
        return warning("We had a problem retrieving this payload")
      end

      if payload.size <= MAX_DELIVERY_CONTENT_SIZE
        GitHub::Colorize.highlight_json(payload)
      else
        warning "We can’t highlight this payload because it’s too large" do
          raw_url = urls.hook_delivery_payload_path(hook, delivery_id)
          helpers.link_to "View raw payload", raw_url, class: "btn btn-sm flash-action"
        end
      end
    end

    def delivery_response_body(*_)
      return if response_body.nil? || response_body.empty?

      if response_body_within_limit?
        helpers.content_tag :pre, response_body.dup.force_encoding("UTF-8").scrub! # rubocop:disable Rails/ViewModelHTML
      else
        warning "Whoops, this response body is too large to display."
      end
    end

    def connection_error?(*_)
      status_code == "0"
    end

    def remote_webhook_host_and_port
      uri = Addressable::URI.parse(hook.url)
      "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end

    def ssl_verification_url
      test_url = "https://www.sslshopper.com/ssl-checker.html#hostname="
      "#{test_url}#{remote_webhook_host_and_port}"
    end

    def can_view_url?
      hook.editable_by?(current_user) || current_user.site_admin?
    end

    private

    def delivery_headers(headers)
      return nil if headers.nil?

      sorted_headers = headers.sort_by { |(header, _)| header.downcase }
      masked_headers = mask_sensitive_headers(sorted_headers)

      html_headers = masked_headers.map do |header, value|
        helpers.safe_join([helpers.content_tag(:strong, "#{header}:"), helpers.escape_once(value)], " ") # rubocop:disable Rails/ViewModelHTML
      end
      helpers.safe_join(html_headers, "\n")
    end

    SENSITIVE_HEADERS = %w(authorization)
    def mask_sensitive_headers(headers)
      headers.each_with_object({}) do |(header, value), masked|
        masked[header] = SENSITIVE_HEADERS.include?(header.underscore) ? "********" : value
      end
    end

    def warning(message)
      block_content = yield if block_given?
      helpers.content_tag(:div, helpers.safe_join([block_content, message], " "), class: "flash flash-warn") # rubocop:disable Rails/ViewModelHTML
    end

    def response_body_within_limit?
      response_body.to_s.size <= MAX_DELIVERY_CONTENT_SIZE
    end
  end
end
