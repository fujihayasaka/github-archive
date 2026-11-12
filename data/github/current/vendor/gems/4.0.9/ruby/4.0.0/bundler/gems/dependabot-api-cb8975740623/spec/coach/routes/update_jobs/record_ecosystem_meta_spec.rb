# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordEcosystemMeta do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:update_job) { FactoryBot.create(:update_job, :processing) }
  let(:ecosystem_name) { "npm_and_yarn" }
  let(:pkg_manager_name) { "npm" }
  let(:pkg_manager_version) { "2.5.1" }
  let(:pkg_manager_raw_version) { "2.5.1-alpha" }
  let(:language_name) { "node" }
  let(:language_version) { "3.5.2" }
  let(:language_raw_version) { "3.5.2-beta" }

  let(:package_manager_data) do
    {
      "name": pkg_manager_name,
      "raw_version": pkg_manager_raw_version,
      "version": pkg_manager_version,
      "requirement": {
        "raw_constraint": ">= 2.0",
        "min_raw_version": "2.0.0-alpha",
        "min_version": "2.0.0",
        "max_raw_version": "3.0.0-beta",
        "max_version": "3.0.0",
      },
    }
  end

  let(:language_data) do
    {
      name: language_name,
      raw_version: language_raw_version,
      version: language_version,
      requirement: {
        raw_constraint: ">= 2.5",
        min_raw_version: "2.5.0-alpha",
        min_version: "2.5.0",
        max_raw_version: "3.2.0-beta",
        max_version: "3.2.0",
      },
    }
  end

  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: [
        {
          ecosystem: {
            name: ecosystem_name,
            package_manager: package_manager_data,
            language: language_data,
          },
        },
      ]
    )
  end

  let(:tags) do
    {
      "ecosystem.name" => "npm_and_yarn",
      "pkg_manager.name" => "npm",
      "pkg_manager.raw_version" => "2.5.1-alpha",
      "pkg_manager.version" => "2.5.1",
      "pkg_manager.requirement.raw_constraint" => ">= 2.0",
      "pkg_manager.requirement.min_raw_version" => "2.0.0-alpha",
      "pkg_manager.requirement.min_version" => "2.0.0",
      "pkg_manager.requirement.max_raw_version" => "3.0.0-beta",
      "pkg_manager.requirement.max_version" => "3.0.0",
      "language.name" => "node",
      "language.raw_version" => "3.5.2-beta",
      "language.version" => "3.5.2",
      "language.requirement.raw_constraint" => ">= 2.5",
      "language.requirement.min_raw_version" => "2.5.0-alpha",
      "language.requirement.min_version" => "2.5.0",
      "language.requirement.max_raw_version" => "3.2.0-beta",
      "language.requirement.max_version" => "3.2.0",
    }
  end

  it "makes a call to send ecosystem metadata to datadog" do
    expect(MetricsClient).to receive(:count).with(
      "update_job.ecosystem_meta", 1, tags: hash_including(tags)
    ).once

    instance.call
  end

  context "when params do not contain an ecosystem name" do
    let(:ecosystem_name) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when package manager data is nil" do
    let(:package_manager_data) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when package manager name is nil" do
    let(:pkg_manager_name) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when package manager version is nil" do
    let(:pkg_manager_version) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when package manager raw_version is nil" do
    let(:pkg_manager_raw_version) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when language name is nil" do
    let(:language_name) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when language version is nil" do
    let(:language_version) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when language raw_version is nil" do
    let(:language_raw_version) { nil }

    it "is a bad request" do
      response = instance.call
      expect(response[0]).to eq 400
    end
  end

  context "when language data is nil" do
    let(:language_data) { nil }

    let(:tags) do
      {
        "ecosystem.name" => "npm_and_yarn",
        "pkg_manager.name" => "npm",
        "pkg_manager.raw_version" => "2.5.1-alpha",
        "pkg_manager.version" => "2.5.1",
        "pkg_manager.requirement.raw_constraint" => ">= 2.0",
        "pkg_manager.requirement.min_raw_version" => "2.0.0-alpha",
        "pkg_manager.requirement.min_version" => "2.0.0",
        "pkg_manager.requirement.max_raw_version" => "3.0.0-beta",
        "pkg_manager.requirement.max_version" => "3.0.0",
      }
    end

    it "makes a call to send ecosystem metadata to datadog" do
      expect(MetricsClient).to receive(:count).with(
        "update_job.ecosystem_meta", 1, tags: hash_including(tags)
      ).once

      instance.call
    end
  end

  context "when optional requirements data is nil" do
    let(:package_manager_data) do
      {
        name: pkg_manager_name,
        raw_version: pkg_manager_raw_version,
        version: pkg_manager_version,
        requirement: nil,
      }
    end

    let(:language_data) do
      {
        name: language_name,
        raw_version: language_raw_version,
        version: language_version,
        requirement: nil,
      }
    end

    let(:tags) do
      {
        "ecosystem.name" => "npm_and_yarn",
        "pkg_manager.name" => "npm",
        "pkg_manager.raw_version" => "2.5.1-alpha",
        "pkg_manager.version" => "2.5.1",
      }
    end

    it "makes a call to send ecosystem metadata to datadog" do
      expect(MetricsClient).to receive(:count).with(
        "update_job.ecosystem_meta", 1, tags: hash_including(tags)
      ).once

      instance.call
    end
  end
end
