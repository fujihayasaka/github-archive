# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordPackageManagerVersion do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params)  do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: { ecosystem: "bundler", "package-managers" => { "bundler" => "2" } },
    )
  end
  let(:update_job) { FactoryBot.create(:update_job, :processing) }

  it "records the package manager version" do
    instance.call

    expect(update_job.reload.metrics_metadata["package_managers"]).to eq({ "bundler" => "2" })
  end
end
