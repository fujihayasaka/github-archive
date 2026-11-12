# frozen_string_literal: true

require "rails_helper"

RSpec.describe DebugService::V1::Handler do
  include ProximaHelpers

  let(:service) do
    DependabotApi::V1::DebugServiceService.new(described_class.new)
  end

  describe "get_encrypted_config_payload" do
    subject(:response) do
      service.call_rpc :GetEncryptedConfigPayload, update_config_id: update_config_id,
                                                   public_key: public_key
    end

    let(:repository_github_id) { 42 }
    let(:update_config_id) { 0 }
    let(:private_key) { RbNaCl::PrivateKey.generate }
    let(:public_key) { Base64.strict_encode64 private_key.public_key }

    let(:package_ecosystem) do
      {
        name: :BUNDLER,
      }
    end
    let!(:repo) do
      FactoryBot.create(:repo,
                        :with_config_file,
                        github_id: repository_github_id)
    end

    it "returns a not found error if the update config id doesn't exist" do
      expect(response).to be_a(Twirp::Error)
      expect(response.code).to be(:not_found)
      expect(response.msg).to eql("UpdateConfig ID not found.")
    end

    context "when update config exists" do
      let!(:ruby_config) do
        FactoryBot.create(:update_config,
                          :active,
                          package_manager: "bundler",
                          target_branch: "master",
                          monitored_files: [
                            "Gemfile",
                            "Gemfile.lock",
                          ],
                          repo: repo)
      end

      let(:update_config_id) { ruby_config.id }

      before do
        stub_proxima_repo_request(repo_id: repo.github_id, fixture: "proxima_repo")

        allow(GitHubHelpers).
          to receive(:access_token_for).
          with(
            account: ruby_config.account,
            repo_ids: [repo.github_id],
            permissions: { contents: "read", metadata: "read" },
          ).
          and_return("secret")
        allow_any_instance_of(DotcomRegistry).to receive(:credentials).and_return(nil) # rubocop:disable RSpec/AnyInstance
      end

      it "responds with encrypted, base64 encoded payload" do # rubocop:disable RSpec/ExampleLength
        expect(response.encrypted_config_payload).not_to be_empty

        host = Dependabot.proxima? ? "staffship-01.ghe.com" : "github.com"
        payload = response.encrypted_config_payload.delete_prefix(EncryptRegistryCredentialsForDebugging::PREFIX)

        expect { Base64.strict_decode64(payload) }.not_to raise_error
        expect(decrypt_credentials(payload)).to contain_exactly(
          {
            "type" => "git_source",
            "host" => host,
            "username" => "x-access-token",
            "password" => "secret",
            "accessible-repos" => [repo.full_name],
          },
          {
            "credential-type" => "git_source",
            "endpoint" => "/update_jobs/#{update_config_id}/create_jit_access",
            "host" => host,
            "type" => "jit_access",
          },
        )
      end
    end

    private

    def decrypt_credentials(creds)
      JSON.parse(
        RbNaCl::SealedBox.from_private_key(private_key).
        decrypt(Base64.strict_decode64(creds))
      )
    end
  end
end
