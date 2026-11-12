# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::CheckUpdateJobProcessing do
  subject(:instance) { described_class.new(context, null_middleware) }

  let(:context) do
    {
      request: instance_double(ActionDispatch::Request),
      update_job: update_job,
    }
  end

  context "with an update job that is processing" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    it { is_expected.to call_next_middleware }

    context "and the update job has cycled through pending_retry" do
      let(:update_job) { FactoryBot.create(:update_job, :pending_retry) }

      before do
        update_job.transition_to!(
          :enqueued,
          hashed_token: "token",
          hashed_credentials_token: "other-token",
        )
        update_job.transition_to!(:processing)
      end

      it { is_expected.to call_next_middleware }
    end
  end

  context "with an update job that is processed" do
    let(:update_job) { FactoryBot.create(:update_job, :processed) }

    it { is_expected.to respond_with_status(204) }
  end

  context "with an update job that is enqueued" do
    let(:update_job) { FactoryBot.create(:update_job, :enqueued) }

    it { is_expected.to respond_with_status(400) }

    context "and the update job has cycled through pending_retry" do
      let(:update_job) { FactoryBot.create(:update_job, :pending_retry) }

      before do
        update_job.transition_to!(
          :enqueued,
          hashed_token: "token",
          hashed_credentials_token: "other-token",
        )
      end

      it { is_expected.to respond_with_status(400) }
    end
  end
end
