# frozen_string_literal: true

require "rails_helper"

RSpec.describe EncryptRegistryCredentialsForDebugging do
  include ProximaHelpers

  let(:update_config) { create(:update_config, package_manager: "npm_and_yarn", all_registries: true) }
  let(:account) { update_config.account }
  let(:private_key) { RbNaCl::PrivateKey.generate }
  let(:public_key) { Base64.strict_encode64(private_key.public_key) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:owner_github_node_id) { "MDEyOk9yZ2FuaXphdGlvbjMwODQ2MzQ1" }
  let(:repo_github_node_id) { "MDEwOlJlcG9zaXRvcnk4ODYzMjMzNA==" }

  before do
    stub_proxima_repo_request(repo_id: update_config.repo.github_id, fixture: "proxima_repo")
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      with(
        account.current_installation_id,
        repo_ids: [update_config.repo.github_id],
        permissions: { contents: "read", metadata: "read" },
      ).
      and_return("secret")
    allow(GitHubHelpers).to receive(:installation_access_token_for).
      with(account.current_installation_id, permissions: nil, repo_ids: nil).
      and_return("unscoped-secret")

    update_config.package_manager = "npm_and_yarn"

    FactoryBot.create(
      :registry,
      source: update_config.repo,
      registry_type: "npm_registry",
      credentials: {
        url: "https://registry.npmjs.org",
        token: "${{secrets.MY_NPM_TOKEN}}",
      }.to_json,
    )
    mock_secrets({ "MY_NPM_TOKEN" => "super secret token" })
  end

  it "encrypts the secrets", :cloud do # rubocop:disable RSpec/ExampleLength
    creds = described_class.new(update_config, public_key).run
    decrypted_credentials = decrypt_credentials(creds)

    expect(decrypted_credentials).to contain_exactly(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "secret",
        "accessible-repos" => [update_config.repo.full_name],
      },
      { "type" => "npm_registry", "registry" => "registry.npmjs.org", "token" => "super secret token" },
      # In this context the JIT access token makes no sense, but it's still returned here.
      {
        "credential-type" => "git_source",
        "endpoint" => "/update_jobs/#{update_config.id}/create_jit_access",
        "host" => "github.com",
        "type" => "jit_access",
      },
    )
  end

  private

  def mock_secrets(secrets_hash)
    allow_any_instance_of(SecretFetcher). # rubocop:disable RSpec/AnyInstance
      to receive(:fetch).with(update_config.repo, owner_github_node_id, repo_github_node_id, *secrets_hash.keys).
      and_return(secrets_hash)

    stub_request(:get, github_url + "user/#{update_config.account.github_id}").
      to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

    stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
      to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)
  end

  def decrypt_credentials(creds)
    encrypted_credential_blob = creds.encrypted_credential_blob.delete_prefix(described_class::PREFIX)
    JSON.parse(
      RbNaCl::SealedBox.from_private_key(private_key).
      decrypt(Base64.strict_decode64(encrypted_credential_blob))
    )
  end
end
