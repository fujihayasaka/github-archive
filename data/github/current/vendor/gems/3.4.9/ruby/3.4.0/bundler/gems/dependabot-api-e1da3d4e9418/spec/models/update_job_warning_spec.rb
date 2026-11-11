# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobWarning, type: :model do
  subject(:update_job_warning) do
    FactoryBot.build(:update_job_warning, update_job: update_job)
  end

  let(:update_job) do
    FactoryBot.create(:update_job, :processed_with_errors)
  end

  describe "validations" do
    it { is_expected.to be_valid }

    context "without warn_type" do
      before { update_job_warning.warn_type = nil }

      it { is_expected.not_to be_valid }
    end

    context "without warn_title" do
      before { update_job_warning.warn_title = nil }

      it { is_expected.not_to be_valid }
    end

    context "without an update_job" do
      before { update_job_warning.update_job = nil }

      it { is_expected.not_to be_valid }
    end
  end

  describe "#warning_hash" do
    subject(:warning_hash) { update_job_warning.warning_hash }

    it "returns a hash compatible with UpdateJobWarningPresenter" do
      expect(warning_hash).to eq(
        "warn_type" => update_job_warning.warn_type,
        "warn_title" => update_job_warning.warn_title,
        "warn_description" => update_job_warning.warn_description,
      )
    end
  end

  describe "#warning_presenter" do
    subject(:warning_presenter) { update_job_warning.warning_presenter }

    it "returns an instance of UpdateJobWarningPresenter" do
      expect(warning_presenter).to be_an_instance_of(UpdateJobWarningPresenter)
      expect(warning_presenter.warning_hash["warn_type"]).
        to eq(update_job_warning.warn_type)
      expect(warning_presenter.warning_hash["warn_title"]).
        to eq(update_job_warning.warn_title)
      expect(warning_presenter.warning_hash["warn_description"]).
        to eq(update_job_warning.warn_description)
    end
  end
end
