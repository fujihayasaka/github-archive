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

  context "with composer values" do
    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "composer-registry",
            url: "https://composer.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "composer-registry",
            url: "https://composer.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "composer-registry",
            url: "https://composer.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "composer-registry",
            url: "https://composer.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with docker values" do
    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "docker-registry",
            url: "https://docker.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "docker-registry",
            url: "https://docker.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "docker-registry",
            url: "https://docker.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "docker-registry",
            url: "https://docker.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with helm values" do
    context "with a username and password" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "helm-registry",
            url: "https://helm.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "helm-registry",
            url: "https://helm.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "helm-registry",
            url: "https://helm.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "helm-registry",
            url: "https://helm.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
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

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry",
            url: "https://npm.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry",
            url: "https://npm.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "npm-registry",
            url: "https://npm.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with nuget values" do
    let(:data) do
      {
        version: 2,
        update_configs: [{
          package_ecosystem: "nuget",
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
            type: "nuget-feed",
            url: "https://nuget.example.com",
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
            type: "nuget-feed",
            url: "https://nuget.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "nuget-feed",
            url: "https://nuget.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "nuget-feed",
            url: "https://nuget.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "nuget-feed",
            url: "https://npm.example.com",
            "jfrog-oidc-provider-name": "some-provider",
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

    context "with Azure OIDC values (tenant-id + client-id)" do
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

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "cargo-registry",
            url: "https://cargo.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "cargo-registry",
            url: "https://cargo.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with goproxy values" do
    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "goproxy-server",
            url: "https://goproxy.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "goproxy-server",
            url: "goproxy.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "goproxy-server",
            url: "https://goproxy.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "goproxy-server",
            url: "https://goproxy.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with hex repository values" do
    context "with key" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "hex-repository",
            url: "https://hex.example.com",
            repo: "my_hex_repository",
            key: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "hex-repository",
            url: "https://hex.example.com",
            repo: "my_hex_repository",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "hex-repository",
            url: "https://hex.example.com",
            repo: "my_hex_repository",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "hex-repository",
            url: "https://hex.example.com",
            repo: "my_hex_repository",
            "jfrog-oidc-provider-name": "some-provider",
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

    context "with Azure OIDC values (tenant-id + client-id)" do
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

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "maven-repository",
            url: "https://maven.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "maven-repository",
            url: "https://maven.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with pub values" do
    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "pub-repository",
            url: "https://pub.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "pub-repository",
            url: "https://pub.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "pub-repository",
            url: "https://pub.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "pub-repository",
            url: "https://pub.example.com",
            "jfrog-oidc-provider-name": "some-provider",
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

    context "with Azure OIDC values (tenant-id + client-id)" do
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

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "python-index",
            url: "https://python.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "python-index",
            url: "https://python.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with rubygems values" do
    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "rubygems-server",
            url: "https://rubygems.example.com",
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
            type: "rubygems-server",
            url: "https://rubygems.example.com",
            username: "some-username",
            password: "some-password",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "rubygems-server",
            url: "https://rubygems.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "rubygems-server",
            url: "https://rubygems.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "rubygems-server",
            url: "https://rubygems.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end

  context "with terraform values" do
    context "with a token" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "terraform-registry",
            url: "https://terraform.example.com",
            token: "abc123",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with Azure OIDC values (tenant-id + client-id)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "terraform-registry",
            url: "https://terraform.example.com",
            "tenant-id": "12345678-1234-1234-1234-123456789012",
            "client-id": "87654321-4321-4321-4321-210987654321",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with AWS OIDC values (aws-region + account-id + role-name + domain + domain-owner)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "terraform-registry",
            url: "https://terraform.example.com",
            "aws-region": "us-west-2",
            "account-id": "123456789012",
            "role-name": "example-role",
            domain: "example.com",
            "domain-owner": "123456789012",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end

    context "with JFrog OIDC values (jfrog-oidc-provider-name + url)" do
      let(:data) do
        {
          version: 2,
          registries: [{
            type: "terraform-registry",
            url: "https://terraform.example.com",
            "jfrog-oidc-provider-name": "some-provider",
          }],
        }
      end

      it { is_expected.to be_truthy }
    end
  end
end
