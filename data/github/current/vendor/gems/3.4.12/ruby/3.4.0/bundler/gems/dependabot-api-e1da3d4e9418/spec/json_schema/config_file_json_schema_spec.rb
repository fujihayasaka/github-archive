# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Config file JSON schema", type: :integration do
  subject(:validate_schema) do
    JSON::Validator.validate!(schema, data,
                              validate_schema: true,
                              version: :draft6,)
  end

  let(:schema) do
    File.read(
      Rails.root.join("config/config_file_json_schema.json"),
    )
  end

  context "with npm values" do
    let(:data) do
      {
        version: 2,
        update_configs: [{
          package_ecosystem: "npm",
          directory: "/",
          schedule: {
            interval: "daily",
          },
        }],
      }
    end

    it { is_expected.to be_truthy }

    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry",
            url: "https://npm.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry",
            url: "https://npm.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry2",
            url: "https://npm.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with cargo values" do
    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "cargo-registry",
            url: "https://cargo.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "cargo-registry",
            url: "cargo.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with maven values" do
    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "maven-repository",
            url: "https://maven.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "maven-repository",
            url: "https://maven.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with python values" do
    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "python-index",
            url: "https://python.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "python-index",
            url: "https://python.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end
end
