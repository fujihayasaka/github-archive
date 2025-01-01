# frozen_string_literal: true

require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def generate_valid_signature(body)
    assert ENV.fetch("GITHUB_WEBHOOK_SECRET")

    digest =
      OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha1"),
        ENV.fetch("GITHUB_WEBHOOK_SECRET"),
        body,
      )

    "sha1=#{digest}"
  end

  def generate_invalid_signature
    "sha1=#{SecureRandom.hex(20)}"
  end

  test "verifies the webhook signature" do
    body = %({"repository":{"full_name":"#{AdvisoryDB.github_advisories_repo}"}})
    invalid_signature = generate_invalid_signature

    post webhook_url, params: body, headers: webhook_headers(:check_suite, body)

    assert_response :success

    assert_raise do
      post webhook_url, params: body, headers: webhook_headers(:check_suite, body, { "X-Hub-Signature" => invalid_signature })

      assert_response :error
    end

    assert_raise do
      post webhook_url, params: body, headers: {}

      assert_response :error
    end
  end

  test "returns a No Content status for non-advisories repos" do
    body = %({"repository":{"full_name":"bogus/repo-name"}})
    post_webhook(body: body, x_github_event: :check_suite)
    assert_response :no_content
  end

  test "returns a No Content status for an unknown event" do
    body = %({"repository":{"full_name":"#{AdvisoryDB.github_advisories_repo}"}})
    post_webhook(body: body, x_github_event: :bogus_event)
    assert_response :no_content
  end

  test "enqueues the ProcessImproveAdvisoryPRJob when it recieves a pull_request open payload" do
    body = webhook_payload(:pull_request_opened)

    assert_enqueued_with(
      job: ProcessImproveAdvisoryPRJob,
      args: [
        pr_number: 1,
        head_sha: "e889c5d9db369c45c397d1a3d66e8bc363ca35ae",
        actor_login: "octocat",
        actor_id: 91620674,
      ],
    ) do
      post_webhook(body: body, x_github_event: :pull_request)
    end

    assert_response :accepted
  end

  test "enqueues the ProcessImproveAdvisoryPRJob when it recieves a pull_request synchronize payload" do
    body = webhook_payload(:pull_request_opened, { action: "synchronize" })

    assert_enqueued_with(
      job: ProcessImproveAdvisoryPRJob,
      args: [
        pr_number: 1,
        head_sha: "e889c5d9db369c45c397d1a3d66e8bc363ca35ae",
        actor_login: "octocat",
        actor_id: 91620674,
      ],
    ) do
      post_webhook(body: body, x_github_event: :pull_request)
    end

    assert_response :accepted
  end

  test "enqueues the ProcessImproveAdvisoryPRJob when it recieves a rerequested checkrun payload" do
    body = webhook_payload(:rerequested_check_run)

    assert_enqueued_with(
      job: ProcessImproveAdvisoryPRJob,
      args: [
        pr_number: 4472,
        head_sha: "2a2ef40c57f37a98741f74f65fe2cd366ba0ca2d",
        actor_login: "brphelps",
        actor_id: 10023676,
        check_run_id: 25596680846,
      ],
    ) do
      post_webhook(body: body, x_github_event: :check_run)

      assert_response :accepted
    end
  end

  private

  def webhook_payload(name, overrides = {})
    filename = Rails.root.join("test/fixtures/webhook_payloads/#{name}.json")
    json = File.read(filename)
    hash = JSON.parse(json)
    hash.deep_merge!(overrides.deep_stringify_keys)
    JSON.dump(hash)
  end

  def webhook_headers(x_github_event, body, overrides = {})
    {
      "Content-Type" => "application/json",
      "X-Hub-Signature" => generate_valid_signature(body),
      "X-GitHub-Event" => x_github_event.to_s,
    }.merge(overrides)
  end

  def post_webhook(body:, x_github_event:)
    headers = webhook_headers(x_github_event, body)
    post webhook_url, params: body,
      headers: headers
  end
end
