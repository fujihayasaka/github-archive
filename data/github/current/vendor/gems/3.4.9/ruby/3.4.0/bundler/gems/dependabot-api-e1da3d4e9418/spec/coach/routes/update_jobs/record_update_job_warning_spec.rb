# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordUpdateJobWarning do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: { "warn-type" => warn_type, "warn-title" => warn_title, "warn-description" => warn_description },
    )
  end
  let(:warn_type) { "deprecated_method" }
  let(:warn_title) { "Deprecated Method Used" }
  let(:warn_description) { "This method will be removed in future versions." }

  context "for a processing update job" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    it { is_expected.to respond_with_status(204) }

    it "creates an update job warning" do
      expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

      update_job_warning = UpdateJobWarning.last
      expect(update_job_warning.warn_type).to eq(warn_type)
      expect(update_job_warning.warn_title).to eq(warn_title)
      expect(update_job_warning.warn_description).to eq(warn_description)
    end

    context "when the update job warning already exists" do
      before do
        FactoryBot.create(
          :update_job_warning,
          update_job: update_job,
          warn_type: warn_type,
          warn_title: warn_title,
          warn_description: warn_description,
        )
      end

      it "does not create another update job warning" do
        expect { instance.call }.not_to change(UpdateJobWarning, :count)
      end
    end

    context "when the warning type is not provided" do
      let(:warn_type) { nil }

      it "logs a validation error" do
        expect(Rails.logger).to receive(:warn).with(
          /Warning creation failed: Validation failed: Warn type can't be blank/
        )

        expect { instance.call }.not_to change(UpdateJobWarning, :count)
      end
    end

    context "with a nil title" do
      let(:warn_title) { nil }

      it "logs a validation error" do
        expect(Rails.logger).to receive(:warn).with(
          /Warning creation failed: Validation failed: Warn title can't be blank/
        )

        expect { instance.call }.not_to change(UpdateJobWarning, :count)
      end
    end

    context "with a blank title" do
      let(:warn_title) { "" }

      it "logs a validation error" do
        expect(Rails.logger).to receive(:warn).with(
          /Warning creation failed: Validation failed: Warn title can't be blank/
        )

        expect { instance.call }.not_to change(UpdateJobWarning, :count)
      end
    end

    context "with a nil description" do
      let(:warn_description) { nil }

      it "creates a warning with an empty description" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_description).to eq("")
      end
    end

    context "with a blank description" do
      let(:warn_description) { "" }

      it "creates a warning with an empty description" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_description).to eq("")
      end
    end

    context "with a very long title" do
      let(:warn_title) { "a" * 300 }

      it "truncates the warning title" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_title.length).to eq(256)
        expect(update_job_warning.warn_title).to end_with("...")
      end
    end

    context "with a very long description" do
      let(:warn_description) { "a" * 7000 }

      it "truncates the warning description" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_description.length).to eq(6500)
        expect(update_job_warning.warn_description).to end_with("...")
      end
    end

    context "with special characters in the title" do
      let(:warn_title) { "!@#$%^&*()_+" }

      it "creates a warning with the special characters intact" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_title).to eq(warn_title)
      end
    end

    context "with special characters in the description" do
      let(:warn_description) { "!@#$%^&*()_+" }

      it "creates a warning with the special characters intact" do
        expect { instance.call }.to change(UpdateJobWarning, :count).by(1)

        update_job_warning = UpdateJobWarning.last
        expect(update_job_warning.warn_description).to eq(warn_description)
      end
    end
  end
end
