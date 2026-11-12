# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::AppInstall do
  let(:base_client) do
    MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIClient.new(
      GitHub::Twirp::Client.new(
        github_api_url: "http://host.docker.internal:3000/api/v3/",
        hmac_key: "dependabotapihmac"
      ).connection
    )
  end

  let(:client) { described_class.new(client: base_client, tenant: tenant) }
  let(:tenant) { create(:account).tenant }
  let(:response_error) { nil }

  describe "#create_repository_install" do
    let(:repository_id) { 123 }
    let(:state) { :INSTALL_STATE_CREATED }
    let(:installation_id) { 456 }

    before do
      allow(base_client).to receive(:create_repository_install).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
                       repository_id: repository_id,
                       state: state,
                       installation_id: installation_id,
                     ),
                     error: response_error,
                   ))
    end

    context "when the request is successful" do
      it "returns repository install data" do
        result = client.create_repository_install(repository_id: repository_id)

        expect(result).to eq(GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
                               repository_id: repository_id,
                               state: state,
                               installation_id: installation_id,
                             ))
        expect(base_client).
          to have_received(:create_repository_install).
          with(MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallRequest.new(
                 repository_id: repository_id,
                 trigger: :INSTALL_TRIGGER_DEPENDENCY_GRAPH_REQUESTED,
               ),
               anything)
      end

      it "reports metrics" do
        client.create_repository_install(repository_id: repository_id)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.app_install.create_repository_install",
          anything,
          tags: { response_code: :ok }
        )
      end
    end

    context "when the server returns an error" do
      let(:response_error) { Twirp::Error.not_found("repository_id") }

      it "raises an Error" do
        expect { client.create_repository_install(repository_id: repository_id) }.
          to raise_error(GitHub::Twirp::AppInstall::Error)
      end

      it "reports metrics" do
        expect { client.create_repository_install(repository_id: repository_id) }.
          to raise_error(GitHub::Twirp::AppInstall::Error)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.app_install.create_repository_install",
          anything,
          tags: { response_code: response_error.code }
        )
      end
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.create_repository_install(repository_id: repository_id)
        expect(base_client).to have_received(:create_repository_install).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect { client.create_repository_install(repository_id: repository_id) }.
            to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.create_repository_install(repository_id: repository_id)
        expect(base_client).to have_received(:create_repository_install).
          with(MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallRequest.new(
                 repository_id: repository_id,
                 trigger: :INSTALL_TRIGGER_DEPENDENCY_GRAPH_REQUESTED,
               ),
               anything)
      end
    end
  end
end
