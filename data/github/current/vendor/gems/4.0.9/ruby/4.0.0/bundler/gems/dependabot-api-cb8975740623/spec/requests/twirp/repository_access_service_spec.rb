# frozen_string_literal: true

require "twirp_helper"

RSpec.describe DependabotApi::V1::RepositoryAccessServiceService,
               type: :request do
  include_context "internal twirp api"

  let(:start_time) { Time.now.utc }
  let(:end_time) { start_time + 1.second }

  before do
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow_any_instance_of(Services::RackApp).
      to receive(:time_now).and_return(start_time, end_time)
  end

  describe "GetRepositoryAccess" do
    before do
      allow_any_instance_of(RepositoryAccessService::V1::Handler).
        to receive(:get_repository_access).
        and_return({ repository_github_ids: [1] })

      rpc_call method: "GetRepositoryAccess"
    end

    it "returns a 200" do
      expect(response.status).to be(200)
    end

    it "renders response" do
      msg = DependabotApi::V1::GetRepositoryAccessResponse.
            decode(response.body)
      expect(msg.repository_github_ids).to contain_exactly(1)
    end
  end

  describe "SetSelectedRepositories" do
    before do
      allow_any_instance_of(RepositoryAccessService::V1::Handler).
        to receive(:set_selected_repositories).
        and_return({})
      rpc_call method: "SetSelectedRepositories"
    end

    it "returns a 200" do
      expect(response.status).to be(200)
    end

    it "renders response" do
      msg = DependabotApi::V1::SetSelectedRepositoriesResponse.
            decode(response.body)
      expect(msg).not_to be_nil
    end
  end
end
