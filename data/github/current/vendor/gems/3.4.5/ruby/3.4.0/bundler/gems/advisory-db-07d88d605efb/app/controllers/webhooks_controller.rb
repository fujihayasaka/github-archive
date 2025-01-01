# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_forgery_protection

  WebhookSignatureMismatch = Class.new(StandardError)

  before_action :verify_signature
  before_action :verify_advisories_repo

  def create
    case request.headers["X-GitHub-Event"]
    when "pull_request"
      case payload[:action]
      when "opened", "synchronize"
        ProcessImproveAdvisoryPRJob.perform_later(
          pr_number: payload[:number],
          head_sha: payload.dig(:pull_request, :head, :sha),
          actor_login: payload.dig(:pull_request, :user, :login),
          actor_id: payload.dig(:pull_request, :user, :id),
        )
        head :accepted
      else
        head :no_content
      end
    when "check_run"
      case payload[:action]
      when "rerequested"
        ProcessImproveAdvisoryPRJob.perform_later(
          pr_number: payload[:check_run][:pull_requests][0][:number],
          head_sha: payload[:check_run][:pull_requests][0].dig(:head, :sha),
          actor_login: payload.dig(:sender, :login),
          actor_id: payload.dig(:sender, :id),
          check_run_id: payload.dig(:check_run, :id),
        )
        head :accepted
      else
        head :no_content
      end
    else
      # We don't handle these events yet.
      head :no_content
    end
  end

  private

  def verify_signature
    actual_signature = request.headers["X-Hub-Signature"].to_s
    expected_digest =
      OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha1"),
        AdvisoryDB.github_webhook_secret,
        request.raw_post,
      )
    expected_signature = "sha1=#{expected_digest}"

    return if Rack::Utils.secure_compare(actual_signature, expected_signature)

    raise WebhookSignatureMismatch
  end

  def verify_advisories_repo
    # We only want to respond to webhooks for the advisories repo, other repos like cvelist are purely for writing to
    head :no_content if payload.dig(:repository, :full_name) != AdvisoryDB.github_advisories_repo
  end

  def payload
    @payload ||= ActionController::Parameters.new(request.request_parameters)
  end

  def current_user_login
    payload.dig(:sender, :login)
  end
end
