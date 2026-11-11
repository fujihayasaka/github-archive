# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobWarningPresenter do
  include PresenterHelper

  subject(:presenter) do
    described_class.new(update_job: update_job, warning_hash: warning_hash)
  end

  let(:warning_hash) do
    { "warn_type" => warn_type, "warn_title" => warn_title, "warn_description" => warn_description }
  end
  let(:warn_type) { "some_warning_type" }
  let(:warn_title) { "Some Warning Title" }
  let(:warn_description) { "Some description about the warning." }
  let(:update_job) { FactoryBot.build_stubbed(:update_job) }

  describe "#issue_type" do
    it "returns the sanitized warn_type" do
      expect(presenter.issue_type).to eq("some_warning_type")
    end
  end

  describe "#issue_title" do
    context "when warn_title is provided" do
      it "returns the sanitized warn_title" do
        expect(presenter.issue_title).to eq("Some Warning Title")
      end
    end

    context "when warn_title contains allowed HTML tags" do
      let(:warn_title) { "<strong>Important Warning</strong>" }

      it "retains allowed HTML tags" do
        expect(presenter.issue_title).to eq("<strong>Important Warning</strong>")
      end
    end

    context "when warn_title is nil" do
      let(:warn_title) { nil }

      it "returns an empty string" do
        expect(presenter.issue_title).to be_empty
      end
    end
  end

  describe "#issue_body" do
    context "when warn_description is provided" do
      it "returns the sanitized warn_description" do
        expect(presenter.issue_body).to eq("Some description about the warning.")
      end
    end

    context "when warn_description contains allowed HTML tags" do
      let(:warn_description) { "<p>This is a <strong>bold</strong> warning.</p>" }

      it "retains allowed HTML tags" do
        expect(presenter.issue_body).to eq("<p>This is a <strong>bold</strong> warning.</p>")
      end
    end

    context "when warn_description is nil" do
      let(:warn_description) { nil }

      it "returns the default warning description" do
        expect(presenter.issue_body).to eq(UpdateJobWarningPresenter::DEFAULT_WARNING_DESCRIPTION)
      end
    end
  end

  describe "special characters handling" do
    context "with special characters in warn_type" do
      let(:warn_type) { "network_unsafe_http<script>" }

      it "removes disallowed tags in warn_type" do
        expect(presenter.issue_type).to eq("network_unsafe_http")
      end
    end

    context "with special characters in warn_title" do
      let(:warn_title) { "<script>alert('XSS');</script>" }

      it "removes the disallowed script tags in warn_title" do
        expect(presenter.issue_title).to eq("alert('XSS');")
      end
    end

    context "with allowed HTML in warn_description" do
      let(:warn_description) { "<div>Some <em>HTML</em> content</div>" }

      it "removes disallowed HTML tags and keeps allowed ones" do
        expect(presenter.issue_body).to eq("<div>Some <em>HTML</em> content</div>")
      end
    end

    context "when warn_description has unsafe attributes" do
      let(:warn_description) { '<a href="javascript:alert(\'XSS\')">Click me</a>' }

      it "removes unsafe attributes but keeps the tag" do
        expect(presenter.issue_body).to eq("<a>Click me</a>")
      end
    end
  end
end
