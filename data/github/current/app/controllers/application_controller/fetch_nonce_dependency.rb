# typed: true
# frozen_string_literal: true

module ApplicationController::FetchNonceDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  NONCE_HEADER = "X-Fetch-Nonce"
  NONCE_TO_VALIDATE_HEADER = "X-Fetch-Nonce-To-Validate"
  GITHUB_REQUEST_ID_HEADER = "X-GitHub-Request-ID"
  VERSION = "v2"

  NONCE_REGEX = /data-nonce="(?<nonce>#{VERSION}:\w{8}-\w{4}-\w{4}-\w{4}-\w{12})"/

  class CurrentNonce < ActiveSupport::CurrentAttributes
    attribute :nonce
  end

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :validate_fetch_nonce
    before_action :set_fetch_nonce
  end

  def current_nonce
    return CurrentNonce.nonce if CurrentNonce.nonce.present?

    generate_nonce
  end

  private

  # This method is used to validate the nonce sent by requests from HTML rendering elements such as <include-fragment>.
  def validate_fetch_nonce
    # Anonymous requests load pages from Varnish, so the nonce may not match what's expected. Since they don't have
    # access to any secure / private data, we can just skip them.
    return unless current_user.present?

    nonce = request.headers[NONCE_HEADER]
    nonce_to_validate = request.headers[NONCE_TO_VALIDATE_HEADER]

    return if nonce.blank? || nonce_to_validate.nil?

    valid = nonce == nonce_to_validate
    should_block = current_user.feature_flag_enabled?(:fetch_nonce_block, default: false) && !valid

    head 403 if should_block

    GitHub.dogstats.increment("browser.fetch.nonce", tags: ["valid:#{valid}", "controller:#{controller_name}", "action:#{action_name}", "version:#{VERSION}", "blocked:#{should_block}"])

    if nonce_to_validate.blank?
      GitHub.dogstats.increment("browser.fetch.nonce.empty", tags: ["controller:#{controller_name}", "action:#{action_name}", "version:#{VERSION}", "blocked:#{should_block}"])
    end

    if !valid
      GitHub.logger.info(
        "Fetch nonce mismatch. Expected: #{nonce}, got: #{nonce_to_validate}.",
        "code.namespace": "ApplicationController::FetchNonceDependency",
        "code.function": "validate_fetch_nonce",
        "gh.request.controller": controller_name,
        "gh.request.action": action_name,
        "gh.request.referer": request.referrer,
        "gh.client.version": request.headers[ApplicationController::ClientVersionDependency::CLIENT_VERSION_HEADER] || "unknown",
        "gh.server.version": GitHubUI::Manifest.new.git_sha,
      )
    end
  end

  # Generates a nonce for the **session**. When soft-navigating, we propagate the fetch nonce to the new page. On
  # hard navigation, we generate a new nonce using a uuid.
  def set_fetch_nonce
    nonce = generate_nonce

    CurrentNonce.nonce = nonce
    Primer::CurrentAttributes.nonce = nonce

    return unless current_user.present?
    return if response.headers["Vary"]&.include?(NONCE_HEADER)

    # Set Vary to ensure browsers won't cache a previous nonce response
    add_headers_to_vary([NONCE_HEADER])
  end

  def generate_nonce
    # Use nonce from request if present
    # This is used in case a protected element like include-fragment loads another protected element
    # and we want to use the same nonce for both. It's also used in the case of a verified-fetch call
    # from React, which may load a protected element from Rails.
    return request.headers[NONCE_HEADER] if request.headers[NONCE_HEADER].present?
    # Use Github request ID to ensure voltron fragments use the same ID
    request_id = request.headers[GITHUB_REQUEST_ID_HEADER]

    uuid = request_id.present? ? generate_uuid_from_seed(request_id) : SecureRandom.uuid

    "#{VERSION}:#{uuid}"
  end

  def generate_uuid_from_seed(seed)
    hash = Digest::SHA256.hexdigest(seed.to_s)

    # Format the hash as a UUID (8-4-4-4-12 format)
    uuid = [
      hash[0..7],
      hash[8..11],
      hash[12..15],
      hash[16..19],
      hash[20..31]
    ].join("-")

    uuid
  end

  # Replaces the nonce in the provided HTML fragment with the current nonce.
  #
  # @param fragment [String] The HTML fragment containing a nonce attribute to be replaced.
  #   The fragment is expected to include a `data-nonce` attribute matching the `NONCE_REGEX`.
  # @return [String] A new HTML fragment with the `data-nonce` attribute updated to the current nonce.
  #   If no `data-nonce` attribute is found, the original fragment is returned unchanged.
  def inject_fragment_fetch_nonce(fragment)
    return fragment unless current_user.present?

    fragment.gsub(NONCE_REGEX) do |match|
      match.sub(T.must(Regexp.last_match)[:nonce], CurrentNonce.nonce)
    end
  end
end
