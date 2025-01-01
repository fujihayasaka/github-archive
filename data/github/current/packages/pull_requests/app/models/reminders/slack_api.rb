# typed: true
# frozen_string_literal: true

module Reminders
  class SlackApi
    EXPIRATION_LEEWAY = 60.seconds

    class << self
      def post_reminder_change_to_channel(reminder_url:, reminder:, user:, action:, timeout: 3)
        raise ArgumentError, "Can't send message to Slack, reminder is not valid" unless reminder.valid?

        payload = {
          github_user_login: user&.login || User.ghost.login,
          action: action,
          reminder_link: reminder_url,
          workspace_id: reminder.slack_workspace.slack_id,
          channel_name: reminder.slack_channel, # Always use Slack Channel name as we want to use this to validate the channel's existence
        }
        service_base = "/_slack" if GitHub.enterprise?
        post("#{service_base}/slack/v2/post_reminder_change", jwt: sign_payload(payload), timeout: timeout)
      end

      def channel_status(channel_id, workspace_id:)
        service_base = "/_slack" if GitHub.enterprise?
        success, response_data = post("#{service_base}/slack/v2/validate_channel", body: { channel_id: channel_id, workspace_id: workspace_id })

        if success
          response_data["status"]
        else
          "unknown"
        end
      end

      private

      def post(path, body: {}, jwt: sign_payload({}), timeout: 3)
        post = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
        post.body = { state: jwt }.merge(body).to_json
        send_request(post, timeout: timeout)
      end

      def send_request(request, timeout: 3)
        integration_uri = URI.parse(GitHub.slack_integration_api_url)
        http = Net::HTTP.new(integration_uri.host, integration_uri.port)

        # These requests will happen in web requests, which have a max of 10s to complete.
        # To make sure we don't brush up against that, let's keep the entire request to ~5s
        # to allow for degradation in other parts of the system.
        # Setting to 3s leaves 2s for the remaining aspects of the request to complete.
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.use_ssl = true

        resp = http.request(request)
        returnable_response = begin
          (resp.body.present? ? JSON.parse(resp.body) : "")
        rescue JSON::ParserError
          resp.body
        end

        [resp.is_a?(Net::HTTPSuccess), returnable_response]
      rescue Net::HTTPError, Net::OpenTimeout, Net::ReadTimeout => e
        [false, e.to_s]
      end

      def sign_payload(payload)
        issued_at = Time.now
        expires_at = issued_at + EXPIRATION_LEEWAY
        payload = payload.merge({
          iat: issued_at.to_i,
          exp: expires_at.to_i,
        })
        payload[:uuid] ||= SecureRandom.urlsafe_base64(20)

        JWT.encode(payload, GitHub.slack_integration_secret, "HS256")
      end
    end
  end
end
