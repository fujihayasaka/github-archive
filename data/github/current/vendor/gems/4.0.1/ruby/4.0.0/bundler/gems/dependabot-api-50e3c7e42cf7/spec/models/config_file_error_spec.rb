# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfigFileError, type: :model do
  subject(:config_file_error) { FactoryBot.build_stubbed(:config_file_error) }

  describe "validations" do
    it { is_expected.to be_valid }

    context "without error_type" do
      before { config_file_error.error_type = nil }

      it { is_expected.not_to be_valid }
    end

    context "without a repo" do
      before { config_file_error.repo = nil }

      it { is_expected.not_to be_valid }
    end
  end

  describe "#error_hash" do
    subject(:error_hash) { config_file_error.error_hash }

    it "returns a hash compatible with ConfigFileErrorPresenter" do
      expect(error_hash).to eq(
        "error-type" => "unparseable_config_file",
        "error-detail" => { "message" => "My message" },
      )
    end
  end

  describe "#error_presenter" do
    subject(:error_presenter) { config_file_error.error_presenter }

    it "returns a hash compatible with ConfigFileErrorPresenter" do
      expect(error_presenter).to be_an_instance_of(ConfigFileErrorPresenter)
      expect(error_presenter.issue_type).
        to eq("unparseable_config_file")
      expect(error_presenter.issue_detail).
        to eq("My message")
    end
  end
end
