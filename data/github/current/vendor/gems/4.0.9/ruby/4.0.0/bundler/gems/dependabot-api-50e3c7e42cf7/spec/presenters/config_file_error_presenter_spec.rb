# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfigFileErrorPresenter do
  subject(:presenter) do
    described_class.new(
      config_file_path: repo.config_file_path,
      error_hash: error_hash
    )
  end

  let(:error_hash) do
    { "error-type" => error_type, "error-detail" => error_detail }
  end
  let(:error_type) { "unparseable_config_file" }
  let(:error_detail) { { "message" => " found unexpected end of stream" } }
  let(:repo) { FactoryBot.build_stubbed(:repo) }

  describe "#issue_type" do
    subject { presenter.issue_type }

    it { is_expected.to eq(error_type) }
  end

  describe "#issue_detail" do
    subject { presenter.issue_detail }

    context "for an unparseable_config_file error" do
      let(:error_type) { "unparseable_config_file" }
      let(:error_detail) { { "message" => "msg" } }

      it { is_expected.to eq("msg") }
    end

    context "for an invalid_config_file error" do
      let(:error_type) { "invalid_config_file" }
      let(:error_detail) { { "message" => "msg" } }

      it { is_expected.to eq("msg") }
    end

    context "for an unexpected error" do
      let(:error_type) { "not_expected" }

      specify { expect { presenter.issue_detail }.to raise_error(/Unexpected/) }
    end
  end

  describe "#issue_title" do
    subject { presenter.issue_title }

    let(:repo) { FactoryBot.build_stubbed(:repo, :with_config_file) }

    context "for an unparseable_config_file error" do
      let(:error_type) { "unparseable_config_file" }

      it { is_expected.to include(".github/dependabot.yml") }
    end

    context "for an invalid_config_file error" do
      let(:error_type) { "invalid_config_file" }

      it { is_expected.to include(".github/dependabot.yml") }
    end

    context "for an unexpected error" do
      let(:error_type) { "not_expected" }

      specify { expect { presenter.issue_title }.to raise_error(/Unexpected/) }
    end
  end

  describe "#issue_body" do
    subject { presenter.issue_body }

    context "for an unparseable_config_file error" do
      let(:error_type) { "unparseable_config_file" }
      let(:error_detail) { { "message" => "msg" } }

      it { is_expected.to include("couldn't parse the config file") }
      it { is_expected.to include("\n\n```\nmsg\n```\n\n") }
    end

    context "for an invalid_config_file error" do
      let(:error_type) { "invalid_config_file" }
      let(:error_detail) { { "message" => "msg" } }

      it { is_expected.to include("error when parsing") }
      it { is_expected.to include("\n\n```\nmsg\n```\n\n") }
    end
  end
end
