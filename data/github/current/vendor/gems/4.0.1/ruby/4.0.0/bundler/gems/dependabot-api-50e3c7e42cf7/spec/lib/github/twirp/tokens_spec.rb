# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::Tokens do
  let(:base_client) do
    MonolithTwirp::Dependabot::Tokens::V1::TokenAPIClient.new(
      GitHub::Twirp::Client.new(
        github_api_url: "http://host.docker.internal:3000/api/v3/",
        hmac_key: "dependabotapihmac"
      ).connection
    )
  end

  let(:client) { described_class.new(client: base_client, tenant: tenant) }
  let(:tenant) { create(:account).tenant }
  let(:response_error) { nil }

  describe "#create_jit_access" do
    let(:account_name) { "monalisa" }
    let(:repo_name) { "smile" }
    let(:permissions) { described_class::DEFAULT_PERMISSIONS }

    let(:token) { "ghs_fakefakefakesuperfake" }

    before do
      allow(base_client).to receive(:create_jit_access).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessResponse.new(
                       token: token,
                       repository_id: 123,
                     ),
                     error: response_error,
                   ))
    end

    context "when the request is successful" do
      it "returns new access token data" do
        result = client.create_jit_access(account_name:, repo_name:)

        expect(result).to eq(GitHub::Twirp::Tokens::JitAccessResponse.new(token:, repository_id: 123))
        expect(base_client).
          to have_received(:create_jit_access).
          with(MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessRequest.new(
                 account_name:, repo_name:, permissions:
               ),
               anything)
      end

      it "reports metrics" do
        client.create_jit_access(account_name:, repo_name:)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.tokens.create_jit_access",
          anything,
          tags: { response_code: :ok }
        )
      end
    end

    context "when the server returns an error" do
      let(:token) { "" }
      let(:response_error) { Twirp::Error.not_found("repo_name") }

      it "raises an Error" do
        expect { client.create_jit_access(account_name:, repo_name:, permissions:) }.
          to raise_error(GitHub::Twirp::Tokens::Error)
      end

      it "reports metrics" do
        expect { client.create_jit_access(account_name:, repo_name:, permissions:) }.
          to raise_error(GitHub::Twirp::Tokens::Error)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.tokens.create_jit_access",
          anything,
          tags: { response_code: response_error.code }
        )
      end
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.create_jit_access(account_name:, repo_name:, permissions:)
        expect(base_client).to have_received(:create_jit_access).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect { client.create_jit_access(account_name:, repo_name:, permissions:) }.
            to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.create_jit_access(account_name:, repo_name:, permissions:)
        expect(base_client).to have_received(:create_jit_access).
          with(MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessRequest.new(
                 account_name:, repo_name:, permissions:
               ),
               anything)
      end
    end
  end
end
