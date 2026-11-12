# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordEcosystemVersions do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params)  do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: { "ecosystem_versions" => { "ruby" => { "min" => 3, "max" => 3.2 } } },
    )
  end
  let(:update_job) { FactoryBot.create(:update_job, :processing) }

  it "records the ecosystem versions" do
    instance.call

    expect(update_job.reload.metrics_metadata["ecosystem_versions"]).to eq({ "ruby" => { "min" => 3, "max" => 3.2 } })
  end
end
