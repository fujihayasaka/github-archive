# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryPayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @repo = create(:repository, :minimal)
    @repo_advisory = create(:published_repository_advisory, repository: @repo)
  end

  test "payload when the repo advisory is published" do
    event_args = {
      action: :published,
      repository_advisory_id: @repo_advisory.id,
    }
    event = Hook::Event::RepositoryAdvisoryEvent.new(event_args)
    payload = Hook::Payload::RepositoryAdvisoryPayload.new(event)
    gen_payload = payload.to_hash
    assert_equal gen_payload[:action], :published
    assert_equal gen_payload[:repository_advisory][:ghsa_id], @repo_advisory.ghsa_id
    assert_equal gen_payload[:repository][:id], @repo.id
    assert_equal gen_payload[:repository_advisory][:severity], @repo_advisory.severity
    assert_equal gen_payload[:sender][:id], @repo_advisory.publisher.id
  end

  test "payload when the repo advisory pvr is reported" do
    event_args = {
      action: :reported,
      repository_advisory_id: @repo_advisory.id,
    }
    event = Hook::Event::RepositoryAdvisoryEvent.new(event_args)
    payload = Hook::Payload::RepositoryAdvisoryPayload.new(event)
    gen_payload = payload.to_hash
    assert_equal gen_payload[:action], :reported
    assert_equal gen_payload[:repository_advisory][:ghsa_id], @repo_advisory.ghsa_id
    assert_equal gen_payload[:repository][:id], @repo.id
    assert_equal gen_payload[:repository_advisory][:severity], @repo_advisory.severity
    assert_equal gen_payload[:sender][:id], @repo_advisory.author.id
  end
end
