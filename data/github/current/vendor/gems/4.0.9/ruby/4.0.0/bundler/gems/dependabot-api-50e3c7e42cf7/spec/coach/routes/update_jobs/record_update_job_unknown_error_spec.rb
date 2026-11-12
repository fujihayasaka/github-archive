# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordUpdateJobUnknownError do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: { "error-type" => error_type, "error-details" => error_detail },
    )
  end
  let(:error_type) { "unknown_error" }
  let(:error_detail) { { "message" => "My message" } }

  before do
    # we report errors from this endpoint, but execution continues
    allow(::Dependabot::Exceptions).
      to receive(:report).
      with(be_a(UpdaterError), be_a(Hash))
  end

  context "for a processing update job" do
    let!(:update_job) { FactoryBot.create(:update_job, :processing) }

    context "with a valid error", :cloud do
      it { is_expected.to respond_with_status(204) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq(error_type)
        expect(update_job_unknown_error.error_details).to eq(error_detail)
      end
    end

    context "with a very long message", :cloud do
      let(:error_detail) { { "message" => "a" * 65536 } }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq(error_type)
        expect(update_job_unknown_error.error_details.fetch("message")).
          to end_with("a...")
      end
    end

    context "with a very long non-string message", :cloud do
      let(:error_detail) { { "message" => ("1" * 65536).to_i } }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq(error_type)
        expect(update_job_unknown_error.error_details.fetch("message")).
          to end_with("1...")
      end
    end

    context "when the unknown error already exists", :cloud do
      before do
        FactoryBot.create(
          :update_job_unknown_error,
          update_job: update_job,
          error_details: error_detail,
        )
      end

      it "does not create another unknown error" do
        expect { instance.call }.not_to change(UpdateJobUnknownError, :count)
      end
    end

    context "with a updater unknown error", :cloud do
      let(:error_type) { "updater_error" }
      let(:error_detail) do
        {
          "message" => "my error message",
        }
      end

      it "creates a updater_error error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("updater_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "my error message" })
      end
    end

    context "with a update files unknown error", :cloud do
      let(:error_type) { "update_files_error" }
      let(:error_detail) do
        {
          "message" => "my update_files_error message",
        }
      end

      it "creates a update_files_error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("update_files_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "my update_files_error message" })
      end
    end

    context "with a snapshots unavailable graph error", :cloud do
      let(:error_type) { "snapshots_unavailable_graph_error" }
      let(:error_detail) do
        {
          "message" => "snapshot server unavailable message",
        }
      end

      it "creates a snapshots_unavailable_graph_error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("snapshots_unavailable_graph_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "snapshot server unavailable message" })
      end
    end

    context "with an unknown update graph error", :cloud do
      let(:error_type) { "unknown_update_graph_error" }
      let(:error_detail) do
        {
          "message" => "something unexpected happened",
        }
      end

      it "creates an unknown_update_graph_error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("unknown_update_graph_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "something unexpected happened" })
      end
    end

    context "with an update graph error", :cloud do
      let(:error_type) { "update_graph_error" }
      let(:error_detail) do
        {
          "message" => "my update_graph_error message",
        }
      end

      it "creates an update_graph_error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("update_graph_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "my update_graph_error message" })
      end
    end

    context "with a unknown error", :cloud do
      let(:error_type) { "unknown_error" }
      let(:error_detail) do
        {
          "message" => "simply unknown error message",
        }
      end

      it "creates an unknown_error" do
        expect { instance.call }.to change(UpdateJobUnknownError, :count).by(1)

        update_job_unknown_error = UpdateJobUnknownError.last
        expect(update_job_unknown_error.error_type).to eq("unknown_error")
        expect(update_job_unknown_error.error_details).to eq({ "message" => "simply unknown error message" })
      end
    end

    it "reports errors to Failbot", :cloud, :enterprise do
      expect(Failbot).
        to receive(:report).
        with(
          be_a(UpdaterError),
          hash_including({ app: ::Dependabot::Exceptions::UPDATER_FAILBOT_APP_NAME })
        )

      instance.call
    end

    it "does not report errors to Failbot in Proxima", :proxima do
      expect(Failbot).not_to receive(:report)

      instance.call
    end
  end
end
