# frozen_string_literal: true

require "vcr"
require "webmock"

GITHUB_ACCESS_TOKEN_URL_PATTERN = %r{\Ahttps://api\.github\.com/app/installations/\d+/access_tokens\z}
GITHUB_LOCALHOST_ACCESS_TOKEN_URL_PATTERN = %r{\Ahttp://api\.github\.localhost/app/installations/\d+/access_tokens\z}
WHITESOURCE_URL = "https://partner.whitesourcesoftware.com/partner"

VCR.configure do |config|
  # uncomment the next line to get a useful debugging log when VCR related tests are acting up
  # config.debug_logger = File.open("#{Rails.root}/log/vcr.log", "w")
  config.hook_into :webmock
  config.cassette_library_dir = "test/cassettes"
  config.default_cassette_options = {
    erb: true,
    update_content_length_header: true,
  }

  config.before_playback do |interaction|
    headers = interaction.response.headers
    headers["Etag"] &&= %("#{SecureRandom.hex}")
    headers["X-Ratelimit-Limit"] &&= ["1000000"]
    headers["X-Ratelimit-Remaining"] &&= ["999999"]
    headers["X-Ratelimit-Reset"] &&= [10.seconds.from_now.to_i.to_s]
  end

  # make access tokens expire 1 hour from now, like a real access token request
  config.before_playback do |interaction|
    if GITHUB_ACCESS_TOKEN_URL_PATTERN.match?(interaction.request.uri) ||
       GITHUB_LOCALHOST_ACCESS_TOKEN_URL_PATTERN.match?(interaction.request.uri)
      begin
        json_body = JSON.parse(interaction.response.body)
      rescue JSON::ParserError
        # NOOP: Not a valid JSON body
      else
        json_body["expires_at"] = 1.hour.from_now.iso8601
        interaction.response.body.replace(json_body.to_json)
      end
    end
  end

  config.before_record do |interaction|
    if GITHUB_ACCESS_TOKEN_URL_PATTERN.match?(interaction.request.uri)
      begin
        json_body = JSON.parse(interaction.response.body)
      rescue JSON::ParserError
        # NOOP: Not a valid JSON body
      else
        json_body["token"] = FactoryBot.generate(:github_access_token)
        interaction.response.body.replace(json_body.to_json)
      end

    elsif WHITESOURCE_URL.eql?(interaction.request.uri)
      begin
        request_body = JSON.parse(interaction.request.body)
      rescue JSON::ParserError
        # NOOP: Not a valid JSON body
      else
        request_body["partnerToken"] = "redacted"
        interaction.request.body.replace(request_body.to_json)
      end

    end
  end

  %w[
    CURATION_SLACK_CHANNEL
    GITHUB_ADVISORIES_REPO
    GITHUB_APP_ID
    GITHUB_APP_NAME
    GITHUB_APP_EMAIL
    GITHUB_APP_INSTALLATION_ID
    GITHUB_CVELIST_REPO
    NVD_API_KEY
    SLACK_API_TOKEN
    SLACK_CHANNEL
  ].each do |var|
    config.filter_sensitive_data(%(<%=ENV["#{var}"]%>)) { ENV.fetch(var, nil) } if ENV[var]
  end

  config.filter_sensitive_data("<REDACTED>") do |interaction|
    authorization_header = interaction.request.headers["Authorization"]
    authorization_header[0].split($FIELD_SEPARATOR, 2)[-1] if authorization_header
  end

  config.filter_sensitive_data("<HMAC>") do |interaction|
    interaction.request.headers["X-Request-Hmac"]&.first || interaction.request.headers["Request-Hmac"]&.first
  end
end
