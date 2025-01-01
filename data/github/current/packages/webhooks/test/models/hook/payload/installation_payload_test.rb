# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadInstallationPayloadTest < GitHub::TestCase
  fixtures do
    @owner  = create :user, login: "owner"

    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @repo        = create(:repository, owner: @owner)
  end

  test "v3" do
    installation = make_integration_installation(integration: @integration, repository: @repo)

    event = Hook::Event::InstallationEvent.new(
      action: :created,
      actor_id: @owner.id,
      installation_id: installation.id,
      integration_id: @integration.id,
    )
    payload = Hook::Payload::InstallationPayload.new event

    v3 = payload.to_hash

    assert_equal :created, v3[:action]
    assert_equal @owner.login, v3[:sender][:login]
    assert_equal @owner.login, v3[:installation][:account][:login]
    assert_match %r{/app/installations/#{installation.id}/access_tokens$},
      v3[:installation][:access_tokens_url]
    assert_match %r{/installation/repositories$},
      v3[:installation][:repositories_url]
    assert_match %r{#{GitHub.url}/settings/installations/#{installation.id}$},
      v3[:installation][:html_url]

    assert_equal 1, v3[:repositories].count
    repo = v3[:repositories].first

    assert repo.key?(:id)
    assert_equal repo[:id], @repo.id

    assert repo.key?(:name)
    assert_equal repo[:name], @repo.name

    assert repo.key?(:full_name)
    assert_equal repo[:full_name], @repo.full_name

    assert repo.key?(:private)
    assert_equal repo[:private], @repo.private?
  end

  test "v3 with requester" do
    org       = create(:organization, admin: @owner)
    repo      = create(:repository, owner: org)
    requester = create(:user)

    installation = make_integration_installation(integration: @integration, repository: repo)

    event = Hook::Event::InstallationEvent.new(
      action: :created,
      actor_id: @owner.id,
      installation_id: installation.id,
      requester_id: requester.id,
      integration_id: @integration.id,
    )

    payload = Hook::Payload::InstallationPayload.new event

    v3 = payload.to_hash

    assert_equal :created, v3[:action]
    assert_equal @owner.login, v3[:sender][:login]
    assert_equal org.login, v3[:installation][:account][:login]

    assert v3.key?(:requester)
    assert_equal requester.login, v3.dig(:requester, :login)
  end

  test "v3 targeting org with multiple repos", skip_if_feature_disabled: :webhooks_installation_payload_repositories_prefill do
    user = create(:user)
    org = create(:organization, admin: user)
    integration = create(:integration, default_permissions: { "metadata" => :read })
    repos = create_list(:repository, 2, owner: org)
    installation = make_integration_installation(integration: integration, target: org)

    event = Hook::Event::InstallationEvent.new(
      action: :created,
      actor_id: user.id,
      installation_id: installation.id,
      integration_id: integration.id,
    )
    payload = Hook::Payload::InstallationPayload.new(event)

    assert_query_count_per_table({ repository_networks: 1 }) do
      payload.to_hash
    end
  end
end
