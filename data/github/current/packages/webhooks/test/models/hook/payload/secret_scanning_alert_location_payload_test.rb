# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanningAlertLocationPayloadSharedMethods
  extend T::Helpers

  def shared_fixture
    @repo = T.unsafe(self).create(:private_repository, owner: @org)
  end

  def shared_setup
    VCR.configure do |c|
      c.default_cassette_options = { serialize_with: :pbjson }
    end
    @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
    Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(false)
    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
  end

  def assert_actor(expected, actual)
    expected.each do |key, value|
      T.unsafe(self).assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  def mock_get_token_locations(token: nil, locations: [], with: nil)
    mock = GitHub::TokenScanning::Service::Client.any_instance
      .expects(:get_token_locations)
      .once

    mock = mock.with(with) if with

    mock.returns(Twirp::ClientResp.new(
      data: GitHub::Proto::SecretScanning::Api::V2::GetTokenLocationsResponse.new(
        token: token,
        locations: locations
      )
    ))
  end

  def create_mock_token(location)
    GitHub::Proto::SecretScanning::Api::V2::Token.new(
      first_location: location,
      created_at: Time.now.utc,
      id: 1,
      label: "Label",
      number: 1,
      repository_id: @repo.id,
      token_type: "some_type",
    )
  end
end

module SecretScanningAlertLocationPayloadSharedTest
  extend ActiveSupport::Concern

  included do
    T.unsafe(self).test "payload for alert repository blob location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        path: "foo.txt",
        commit_oid: "e0e8de1dda7be53ead3a962518d8c4775973d48c",
        blob_oid: "7d7d5bd91e0039acffb385ea92f48ad18d92e788",
        start_line: 1,
        end_line: 2,
        start_column: 3,
        end_column: 4,
        content_type: 1
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "commit", location_payload[:type]
      T.unsafe(self).assert_equal location.path, location_payload[:details][:path]
      T.unsafe(self).assert_equal location.blob_oid, location_payload[:details][:blob_sha]
      T.unsafe(self).assert_equal location.commit_oid, location_payload[:details][:commit_sha]
      T.unsafe(self).assert_equal token.number, alert_payload[:number]
      T.unsafe(self).assert_equal "#{GitHub.api_url}/repos/#{@repo.name_with_display_owner}/git/blobs/#{location.blob_oid}", location_payload[:details][:blob_url]
      T.unsafe(self).assert_equal "#{GitHub.api_url}/repos/#{@repo.name_with_display_owner}/git/commits/#{location.commit_oid}", location_payload[:details][:commit_url]
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise? #here
    end

    T.unsafe(self).test "payload for alert wiki blob location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        path: "home.md",
        commit_oid: "e0e8de1dda7be53ead3a962518d8c4775973d48c",
        blob_oid: "7d7d5bd91e0039acffb385ea92f48ad18d92e788",
        start_line: 1,
        end_line: 2,
        start_column: 3,
        end_column: 4,
        content_type: 15
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "wiki_commit", location_payload[:type]
      T.unsafe(self).assert_equal location.path, location_payload[:details][:path]
      T.unsafe(self).assert_equal location.blob_oid, location_payload[:details][:blob_sha]
      T.unsafe(self).assert_equal location.commit_oid, location_payload[:details][:commit_sha]
      T.unsafe(self).assert_equal token.number, alert_payload[:number]
      T.unsafe(self).assert_equal "#{GitHub.url}/#{@repo.name_with_display_owner}/wiki/#{File.basename(location.path, ".*")}/#{location.commit_oid}", location_payload[:details][:page_url]
      T.unsafe(self).assert_equal "#{GitHub.url}/#{@repo.name_with_display_owner}/wiki/_compare/#{location.commit_oid}", location_payload[:details][:commit_url]
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise? #here
    end

    T.unsafe(self).test "payload for alert issue title location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 9,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "issue_title", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:issue_title_url], "#{@repo.name_with_display_owner}/issues/#{location.content_number}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert issue body location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 10,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "issue_body", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:issue_body_url], "#{@repo.name_with_display_owner}/issues/#{location.content_number}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert issue comment location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 11,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "issue_comment", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:issue_comment_url], "#{@repo.name_with_display_owner}/issues/comments/#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert discussion title location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 12,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "discussion_title", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:discussion_title_url], "#{@repo.name_with_display_owner}/discussions/#{location.content_number}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert discussion body location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 13,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "discussion_body", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:discussion_body_url], "#{@repo.name_with_display_owner}/discussions/#{location.content_number}#discussion-#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert discussion comment location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 14,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "discussion_comment", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:discussion_comment_url], "#{@repo.name_with_display_owner}/discussions/#{location.content_number}#discussioncomment-#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert pr title location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 4,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "pull_request_title", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:pull_request_title_url], "#{@repo.name_with_display_owner}/pulls/#{location.content_number}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert pr body location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 5,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "pull_request_body", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:pull_request_body_url], "#{@repo.name_with_display_owner}/pulls/#{location.content_number}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert pr comment location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 6,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "pull_request_comment", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:pull_request_comment_url], "#{@repo.name_with_display_owner}/issues/comments/#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert pr review location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 8,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "pull_request_review", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:pull_request_review_url], "#{@repo.name_with_display_owner}/pulls/#{location.content_number}/reviews/#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end

    T.unsafe(self).test "payload for alert pr review comment location created" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
        content_number: 1,
        content_id: 1,
        content_type: 7,
      )
      token = T.unsafe(self).create_mock_token(location)
      T.unsafe(self).mock_get_token_locations(token: token, locations: [location])

      event_args = {
        action: :created,
        repository_id: @repo.id,
        alert_number: token.number,
        location_id: 1,
      }
      event = Hook::Event::SecretScanningAlertLocationEvent.new(event_args)
      payload = Hook::Payload::SecretScanningAlertLocationPayload.new(event)
      v3 = payload.to_hash

      T.unsafe(self).assert_equal :created, v3[:action]

      location_payload = v3[:location]
      alert_payload = v3[:alert]
      expected_user = Api::Serializer.serialize(:simple_user_hash, User.find_by(login: "github"))

      T.unsafe(self).assert_equal "pull_request_review_comment", location_payload[:type]
      T.unsafe(self).assert_includes location_payload[:details][:pull_request_review_comment_url], "#{@repo.name_with_display_owner}/pulls/comments/#{location.content_id}"
      T.unsafe(self).assert_actor(expected_user, v3[:sender]) unless GitHub.multi_tenant_enterprise?
    end
  end
end

class SecretScanningAlertLocationPayloadTest < GitHub::TestCase
  include SecretScanningAlertLocationPayloadSharedTest
  include SecretScanningAlertLocationPayloadSharedMethods

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user, login: "github")
    shared_fixture
  end

  setup do
    shared_setup
  end
end

class SecretScanningAlertLocationPayloadMultiTenantTest < GitHub::TestCase
  include SecretScanningAlertLocationPayloadSharedTest
  include SecretScanningAlertLocationPayloadSharedMethods

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    on_multi_tenant_enterprise do
      @user = create :emu
      @business = @user.enterprise_managed_business
      @org = create(:organization, business: @business, admin: @user, login: "github")
      shared_fixture
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
    shared_setup
  end
end
