# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry, type: :model do
  subject(:registry) do
    FactoryBot.build_stubbed(:registry)
  end

  let!(:repo) { FactoryBot.build(:repo) }

  describe "TYPES_FOR_PACKAGE_MANAGER" do
    PackageManagers::ALL.each do |pm|
      it "includes #{pm}" do
        expect { described_class::TYPES_FOR_PACKAGE_MANAGER.fetch(pm) }.
          not_to raise_error
      end
    end
  end

  describe "#source" do
    context "is account" do
      before { subject.source = repo.account }

      it { is_expected.to be_valid }
    end

    context "is repo" do
      before { subject.source = repo }

      it { is_expected.to be_valid }
    end

    context "is other" do
      before { subject.source = FactoryBot.build(:pull_request) }

      it { is_expected.not_to be_valid }
    end
  end

  describe "validations" do
    it { is_expected.to be_valid }

    describe "#credentials" do
      context "with no credentials" do
        before { registry.credentials = "null" }

        it { is_expected.not_to be_valid }
      end

      context "with a somewhat long string" do
        before { registry.credentials = creds.to_json }

        let(:creds) do
          { "url" => ("a" * 2001) + ".com", "token" => "${{secrets.TOKEN}}" }
        end

        it { is_expected.to be_valid }
      end

      context "with a really long string" do
        before { registry.credentials = creds.to_json }

        let(:creds) do
          { "host" => ("a" * 3001) + ".com", "token" => "${{secrets.TOKEN}}" }
        end

        it { is_expected.not_to be_valid }
      end

      context "with invalid JSON" do
        before { registry.credentials = "not_json" }

        it { is_expected.not_to be_valid }
      end

      context "with a git_source" do
        before { registry.registry_type = "git_source" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "gem.fury.io",
            "username" => "a",
            "password" => "${{secrets.github_SECRET}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "username" => "a", "password" => "${{secrets.github_SECRET}}" } }

          it { is_expected.not_to be_valid }
        end

        context "and no login details" do
          let(:creds_hash) { { "url" => "gem.fury.io" } }

          it { is_expected.not_to be_valid }
        end

        context "and a github url" do
          let(:creds_hash) do
            {
              "url" => "github.com",
              "username" => "a",
              "password" => "${{secrets.github_SECRET}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a url" do
          let(:creds_hash) do
            {
              "url" => "my.nonstandard.registry",
              "username" => "a",
              "password" => "${{secrets.github_SECRET}}",
            }
          end

          it { is_expected.to be_valid }

          context "that includes a path" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry/some-path",
                "username" => "a",
                "password" => "${{secrets.github_SECRET}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "that includes a trailing slash" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry/",
                "username" => "a",
                "password" => "${{secrets.github_SECRET}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a port" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry:443",
                "username" => "a",
                "password" => "${{secrets.github_SECRET}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a protocol" do
            let(:creds_hash) do
              {
                "url" => "https://my.nonstandard.registry",
                "username" => "a",
                "password" => "${{secrets.github_SECRET}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a protocol and port" do
            let(:creds_hash) do
              {
                "url" => "https://my.nonstandard.registry:8443",
                "username" => "a",
                "password" => "${{secrets.github_SECRET}}",
              }
            end

            it { is_expected.to be_valid }
          end
        end

        context "and a plaintext password" do
          let(:creds_hash) do
            {
              "url" => "github.com",
              "username" => "a",
              "password" => "token-that-is-in-plaintext-oh-dear",
            }
          end

          it { is_expected.not_to be_valid }
        end
      end

      context "with a rubygems_server" do
        before { registry.registry_type = "rubygems_server" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "gem.fury.io",
            "token" => "${{secrets.GEMFURY}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "token" => "${{secrets.GEMFURY}}" } }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no login details" do
          let(:creds_hash) { { "url" => "gem.fury.io" } }

          it { is_expected.not_to be_valid }
        end

        context "and login details instead of a token" do
          let(:creds_hash) do
            {
              "url" => "gem.fury.io",
              "username" => "a",
              "password" => "b",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a github url" do
          let(:creds_hash) do
            {
              "url" => "github.com/something",
              "token" => "${{secrets.TOKEN}}",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and a github package registry url" do
          let(:creds_hash) do
            {
              "url" => "rubygems.pkg.github.com/account",
              "token" => "${{secrets.TOKEN}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a github.com in the path" do
          let(:creds_hash) do
            {
              "url" => "acme.com/mirrors/github.com",
              "token" => "${{secrets.TOKEN}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a protocol" do
          let(:creds_hash) do
            {
              "url" => "https://gem.fury.io",
              "token" => "${{secrets.TOKEN}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a setting as the url" do
          let(:creds_hash) { { "url" => "ssl_verify_mode", "token" => false } }

          it { is_expected.not_to be_valid }
        end
      end

      context "with a docker_registry" do
        before { registry.registry_type = "docker_registry" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "a-host.io:5000",
            "username" => "a",
            "password" => "b",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "username" => "a", "password" => "b" } }

          it { is_expected.not_to be_valid }
        end

        context "and no login details" do
          let(:creds_hash) { { "url" => "a-host.io:5000" } }

          it { is_expected.not_to be_valid }
        end

        context "and a google container registry password" do
          let(:creds_hash) do
            {
              "url" => "a-host.io:5000",
              "username" => username,
              "password" => "gclouddockertoken:such_token",
            }
          end

          context "and an invalid username" do
            let(:username) { "some_user" }

            it { is_expected.not_to be_valid }
          end

          context "and _json_key as the username" do
            let(:username) { "_json_key" }

            it { is_expected.to be_valid }
          end
        end

        context "and a url containing protocol" do
          let(:creds_hash) do
            {
              "url" => "https://a-host.io:5000",
              "username" => "a",
              "password" => "b",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end
      end

      context "with a helm_registry" do
        before { registry.registry_type = "helm_registry" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "a-host.io:5000",
            "username" => "a",
            "password" => "b",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "username" => "a", "password" => "b" } }

          it { is_expected.not_to be_valid }
        end

        context "and no login details" do
          let(:creds_hash) { { "url" => "a-host.io:5000" } }

          it { is_expected.not_to be_valid }
        end

        context "with a path" do
          let(:creds_hash) do
            {
              "url" => "https://raw.githubusercontent.com/some_private_repo/main",
              "username" => "a",
              "password" => "b",
            }
          end

          it { is_expected.to be_valid }
        end

        context "with a url containing protocol" do
          let(:creds_hash) do
            {
              "url" => "https://a-host.io:5000",
              "username" => "a",
              "password" => "b",
            }
          end

          it { is_expected.to be_valid }
        end

        context "with a localhost url" do
          let(:creds_hash) do
            {
              "url" => "https://localhost:5000",
              "username" => "a",
              "password" => "b",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end
      end

      context "with an npm_registry" do
        before { registry.registry_type = "npm_registry" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "registry.npmjs.org",
            "token" => "${{secrets.NPM_TOKEN}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "token" => "${{secrets.NPM_TOKEN}}" } }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and a token in quotes" do
          let(:creds_hash) do
            {
              "url" => "registry.npmjs.org",
              "token" => '"${{secrets.NPM_TOKEN}}"',
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and a token that is base64 encoded Basic auth" do
          let(:creds_hash) do
            {
              "url" => "registry.npmjs.org",
              "token" => "bXk6dG9rZW4=",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and a custom url" do
          let(:creds_hash) do
            {
              "url" => "my.nonstandard.registry",
              "token" => "${{secrets.NPM_TOKEN}}",
            }
          end

          it { is_expected.to be_valid }

          context "that includes a path" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry/some-path",
                "token" => "${{secrets.NPM_TOKEN}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a port" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry:443",
                "token" => "${{secrets.NPM_TOKEN}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a protocol" do
            let(:creds_hash) do
              {
                "url" => "https://my.nonstandard.registry/",
                "token" => "${{secrets.NPM_TOKEN}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes a protocol and path" do
            let(:creds_hash) do
              {
                "url" => "https://my.nonstandard.registry:8443/",
                "token" => "${{secrets.NPM_TOKEN}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "that includes non-ascii characters" do
            let(:creds_hash) do
              {
                "url" => "my.nonstandard.registry.👹.com",
                "token" => "${{secrets.NPM_TOKEN}}",
              }
            end

            it { is_expected.not_to be_valid }
          end
        end

        context "that includes username+password" do
          let(:creds_hash) do
            {
              "url" => "registry.acme.org",
              "username" => "developer",
              "password" => "${{secrets.NPM_TOKEN}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "that includes username+token" do
          let(:creds_hash) do
            {
              "url" => "registry.acme.org",
              "username" => "developer",
              "token" => "${{secrets.NPM_TOKEN}}",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "with Azure OIDC credentials (tenant-id + client-id)" do
          let(:creds_hash) do
            {
              "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
              "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
              "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
            }
          end

          it { is_expected.to be_valid }

          context "with literal tenant-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "tenant-id" => "12345678-1234-1234-1234-123456789012",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with literal client-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => "87654321-4321-4321-4321-210987654321",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with invalid tenant-id format (not a GUID)" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "tenant-id" => "invalid-tenant-id",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted tenant-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "tenant-id" => '"${{secrets.AZURE_TENANT_ID}}"',
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted client-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with a token" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "token" => "some-token",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with a username and password" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry/",
                "username" => "some-token",
                "password" => "some-password",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with a cargo registry" do
        before { registry.registry_type = "cargo_registry" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "registry" => "cargo-registry-name",
            "url" => "https://cargo.example.com/path",
            "token" => "${{secrets.TOKEN}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { super().except("url") }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no token" do
          let(:creds_hash) { super().except("token") }

          it { is_expected.not_to be_valid }
        end

        context "and a plaintext token" do
          let(:creds_hash) { super().merge({ "token" => "not-so-secret" }) }

          it { is_expected.not_to be_valid }
        end

        context "with Azure OIDC credentials (tenant-id + client-id)" do
          let(:creds_hash) do
            {
              "registry" => "cargo-registry-name",
              "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
              "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
              "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
            }
          end

          it { is_expected.to be_valid }

          context "with literal tenant-id as GUID" do
            let(:creds_hash) do
              {
                "registry" => "cargo-registry-name",
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
                "tenant-id" => "12345678-1234-1234-1234-123456789012",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with literal client-id as GUID" do
            let(:creds_hash) do
              {
                "registry" => "cargo-registry-name",
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => "87654321-4321-4321-4321-210987654321",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with invalid tenant-id format (not a GUID)" do
            let(:creds_hash) do
              {
                "registry" => "cargo-registry-name",
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
                "tenant-id" => "not-a-valid-tenant",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted tenant-id" do
            let(:creds_hash) do
              {
                "registry" => "cargo-registry-name",
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
                "tenant-id" => '"${{secrets.AZURE_TENANT_ID}}"',
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted client-id" do
            let(:creds_hash) do
              {
                "registry" => "cargo-registry-name",
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/cargo/index",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with a goproxy_server" do
        before { registry.registry_type = "goproxy_server" }
        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://goproxy.example.com",
            "username" => "user@example.com",
            "password" => "${{secrets.GOPROXY_PASSWORD}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { super().except("url") }

          it { is_expected.not_to be_valid }
        end

        context "and no password" do
          let(:creds_hash) { super().except("password") }

          it { is_expected.not_to be_valid }
        end

        context "and no username" do
          let(:creds_hash) { super().except("username") }

          it { is_expected.not_to be_valid }
        end

        context "and no authentication" do
          let(:creds_hash) { super().except("username", "password") }

          it { is_expected.not_to be_valid }
        end
      end

      context "with a pub repository" do
        before { registry.registry_type = "pub_repository" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://pub.example.com/path",
            "token" => "${{secrets.TOKEN}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { super().except("url") }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no token" do
          let(:creds_hash) { super().except("token") }

          it { is_expected.not_to be_valid }
        end

        context "and a plaintext token" do
          let(:creds_hash) { super().merge({ "token" => "not-so-secret" }) }

          it { is_expected.not_to be_valid }
        end
      end

      context "with a python index" do
        before { registry.registry_type = "python_index" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
            "replaces-base" => false,
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "replaces-base" => false } }

          it { is_expected.not_to be_valid }
        end

        context "and a bad URL" do
          let(:creds_hash) do
            {
              "url" => "ftp://pypi.weasyldev.com/weasyl/source/+simple",
              "replaces-base" => false,
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and a URL including a Gemfury secret" do
          let(:creds_hash) do
            {
              "url" => "https://gem.fury.io/secret/greysteil/",
              "replaces-base" => false,
            }
          end

          it { is_expected.not_to be_valid }

          context "as basic auth" do
            let(:creds_hash) do
              {
                "url" => "https://secret@gem.fury.io/greysteil/",
                "replaces-base" => false,
              }
            end

            it { is_expected.not_to be_valid }
          end
        end

        context "with Azure OIDC credentials (tenant-id + client-id)" do
          let(:creds_hash) do
            {
              "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
              "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
              "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
            }
          end

          it { is_expected.to be_valid }

          context "with literal tenant-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
                "tenant-id" => "12345678-1234-1234-1234-123456789012",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with literal client-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => "87654321-4321-4321-4321-210987654321",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with invalid tenant-id format (not a GUID)" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
                "tenant-id" => "not-a-valid-tenant",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted tenant-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
                "tenant-id" => '"${{secrets.AZURE_TENANT_ID}}"',
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted client-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/pypi/simple/",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with a maven repository" do
        before { registry.registry_type = "maven_repository" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://maven.oscato.com/content/groups/private",
            "username" => "dependabot",
            "password" => "dependabotPassword",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) do
            {
              "username" => "dependabot",
              "password" => "dependabotPassword",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and a bad URL" do
          let(:creds_hash) do
            {
              "url" => "ftp://maven.oscato.com/content/groups/private",
              "username" => "dependabot",
              "password" => "dependabotPassword",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no username" do
          let(:creds_hash) do
            {
              "url" => "https://maven.oscato.com/content/groups/private",
              "password" => "dependabotPassword",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and no password" do
          let(:creds_hash) do
            {
              "url" => "https://maven.oscato.com/content/groups/private",
              "username" => "dependabot",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and neither a username nor a password" do
          let(:creds_hash) do
            {
              "url" => "https://maven.oscato.com/content/groups/private",
            }
          end

          it { is_expected.to be_valid }
        end

        context "with Azure OIDC credentials (tenant-id + client-id)" do
          let(:creds_hash) do
            {
              "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
              "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
              "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
            }
          end

          it { is_expected.to be_valid }

          context "with literal tenant-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
                "tenant-id" => "12345678-1234-1234-1234-123456789012",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with literal client-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => "87654321-4321-4321-4321-210987654321",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with invalid tenant-id format (not a GUID)" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
                "tenant-id" => "not-a-valid-tenant",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted tenant-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
                "tenant-id" => '"${{secrets.AZURE_TENANT_ID}}"',
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted client-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/maven/v1",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with a dotnet repository" do
        before { registry.registry_type = "nuget_feed" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://maven.oscato.com/content/groups/private",
            "token" => "${{secrets.PASSWORD}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "token" => "dependabot:password" } }

          it { is_expected.not_to be_valid }
        end

        context "and a bad URL" do
          let(:creds_hash) do
            {
              "url" => "ftp://maven.oscato.com/content/groups/private",
              "token" => "dependabot:password",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no token" do
          let(:creds_hash) do
            { "url" => "https://maven.oscato.com/content/groups/private" }
          end

          it { is_expected.to be_valid }
        end

        context "and a token base is base64 encoded Basic auth" do
          let(:creds_hash) do
            {
              "url" => "https://maven.oscato.com/content/groups/private",
              "token" => "bXk6dG9rZW4=",
            }
          end

          it { is_expected.not_to be_valid }
        end

        context "with Azure OIDC credentials (tenant-id + client-id)" do
          let(:creds_hash) do
            {
              "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
              "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
              "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
            }
          end

          it { is_expected.to be_valid }

          context "with literal tenant-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
                "tenant-id" => "12345678-1234-1234-1234-123456789012",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with literal client-id as GUID" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => "87654321-4321-4321-4321-210987654321",
              }
            end

            it { is_expected.to be_valid }
          end

          context "with invalid tenant-id format (not a GUID)" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
                "tenant-id" => "not-a-valid-tenant",
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted tenant-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
                "tenant-id" => '"${{secrets.AZURE_TENANT_ID}}"',
                "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
              }
            end

            it { is_expected.not_to be_valid }
          end

          context "with quoted client-id" do
            let(:creds_hash) do
              {
                "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
                "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
                "client-id" => '"${{secrets.AZURE_CLIENT_ID}}"',
              }
            end

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with a composer registry" do
        before { registry.registry_type = "composer_repository" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "packages.dekodes.no",
            "username" => "user",
            "password" => "${{secrets.SOME_PASSWORD}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no url" do
          let(:creds_hash) { { "username" => "a", "password" => "${{secrets.SOME_PASSWORD}}" } }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no login details" do
          let(:creds_hash) { { "url" => "packages.dekodes.no" } }

          it { is_expected.not_to be_valid }
        end

        context "and a plaintext password" do
          let(:creds_hash) { { "url" => "packages.dekodes.no", "username" => "a", "password" => "dadada" } }

          it { is_expected.not_to be_valid }
        end

        context "and a url that includes a path" do
          let(:creds_hash) do
            {
              "url" => "packages.dekodes.no/some-path",
              "username" => "a",
              "password" => "${{secrets.SOME_PASSWORD}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a url that includes a trailing slash" do
          let(:creds_hash) do
            {
              "url" => "packages.dekodes.no/",
              "username" => "a",
              "password" => "${{secrets.SOME_PASSWORD}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a url that includes a port" do
          let(:creds_hash) do
            {
              "url" => "packages.dekodes.no:443",
              "username" => "a",
              "password" => "${{secrets.SOME_PASSWORD}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a url that includes a protocol" do
          let(:creds_hash) do
            {
              "url" => "https://packages.dekodes.no",
              "username" => "a",
              "password" => "${{secrets.SOME_PASSWORD}}",
            }
          end

          it { is_expected.to be_valid }
        end

        context "and a url that includes a protocol, a port, and a path" do
          let(:creds_hash) do
            {
              "url" => "https://packages.dekodes.no:8443/some-path",
              "username" => "a",
              "password" => "${{secrets.SOME_PASSWORD}}",
            }
          end

          it { is_expected.to be_valid }
        end
      end

      context "with a hex organization" do
        before { registry.registry_type = "hex_organization" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "organization" => "acme",
            "key" => "${{secrets.KEY}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no organization" do
          let(:creds_hash) { { "key" => "${{secrets.KEY}}" } }

          it { is_expected.not_to be_valid }
        end

        context "and no key" do
          let(:creds_hash) { { "organization" => "acme" } }

          it { is_expected.not_to be_valid }
        end

        context "and a plaintext key" do
          let(:creds_hash) do
            {
              "organization" => "acme",
              "key" => "secret",
            }
          end

          it { is_expected.not_to be_valid }
        end
      end

      context "with a hex repository" do
        before { registry.registry_type = "hex_repository" }

        before { registry.credentials = creds_hash.to_json }

        let(:creds_hash) do
          {
            "url" => "https://hex.example.com",
            "repo" => "my_hex_repository",
            "public-key-fingerprint" => "${{secrets.PUBLIC_KEY}}",
            "auth-key" => "${{secrets.KEY}}",
          }
        end

        it { is_expected.to be_valid }

        context "and no repo" do
          let(:creds_hash) { super().except("repo") }

          it { is_expected.not_to be_valid }
        end

        context "and no url" do
          let(:creds_hash) { super().except("url") }

          it { is_expected.not_to be_valid }
        end

        context "and an invalid url" do
          let(:creds_hash) { super().merge({ "url" => "${{secrets.UNSUPPORTED_FIELD_FOR_SECRETS}}" }) }

          it { is_expected.not_to be_valid }
        end

        context "and no auth-key" do
          let(:creds_hash) { super().except("auth-key") }

          it { is_expected.not_to be_valid }
        end

        context "and no public-key-fingerprint" do
          let(:creds_hash) { super().except("public-key-fingerprint") }

          it { is_expected.to be_valid }
        end

        context "and a plaintext auth-key" do
          let(:creds_hash) { super().merge({ "auth-key" => "not-so-secret" }) }

          it { is_expected.not_to be_valid }
        end

        context "and a plaintext public-key-fingerprint" do
          let(:creds_hash) { super().merge({ "public-key-fingerprint" => "not-so-secret" }) }

          it { is_expected.to be_valid }
        end
      end

      context "with a terraform_registry" do
        before { registry.registry_type = "terraform_registry" }

        it "is valid" do
          registry.credentials = {
            url: "https://terraform.example.org",
            token: "${{secrets.TOKEN}}",
          }.to_json

          expect(registry).to be_valid
        end

        it "is invalid without a url" do
          registry.credentials = { token: "${{secrets.TOKEN}}" }.to_json

          expect(registry).to be_invalid
          expect(registry.errors[:base]).to be_present
        end

        it "is invalid with an invalid url" do
          registry.credentials = { url: "invalid", token: "${{secrets.TOKEN}}" }.to_json

          expect(registry).to be_invalid
          expect(registry.errors[:base]).to be_present
        end

        it "is invalid without a token" do
          registry.credentials = { url: "https://example.org" }.to_json

          expect(registry).to be_invalid
          expect(registry.errors[:base]).to be_present
        end

        it "is invalid with a hard coded token" do
          registry.credentials = { url: "invalid", token: "raw-token" }.to_json

          expect(registry).to be_invalid
          expect(registry.errors[:base]).to be_present
        end
      end
    end

    context "with an existing registry on account" do
      let!(:account) { FactoryBot.build(:account) }
      let!(:existing_registry) { FactoryBot.create(:registry, source: account) }

      context "duplicated in the same account" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: existing_registry.source,
          )
        end

        it { is_expected.not_to be_valid }
      end

      context "duplicated by a different account" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
          )
        end

        it { is_expected.to be_valid }
      end

      context "duplicated by a repo in account" do
        subject(:registry) do
          repo.account = existing_registry.source
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: repo,
          )
        end

        it { is_expected.not_to be_valid }
      end

      context "duplicated by a repo in a different account" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: repo,
          )
        end

        it { is_expected.to be_valid }
      end
    end

    context "with an existing registry on repo" do
      let!(:existing_registry) do
        FactoryBot.create(:registry, source: repo)
      end

      context "duplicated in the same repo" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: repo,
          )
        end

        it { is_expected.not_to be_valid }
      end

      context "duplicated in a different repo" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: another_repo,
          )
        end

        let(:another_repo) { FactoryBot.build(:repo) }

        it { is_expected.to be_valid }
      end

      context "duplicated in the repo's account" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: repo.account,
          )
        end

        it { is_expected.not_to be_valid }
      end

      context "duplicated in a different account" do
        subject(:registry) do
          FactoryBot.build(
            :registry,
            name: existing_registry.name,
            source: another_account,
          )
        end

        let(:another_account) { FactoryBot.build(:account) }

        it { is_expected.to be_valid }
      end
    end
  end

  describe "#serialized_credentials" do
    subject(:serialized_credentials) { registry.serialized_credentials(include_metadata: true) }

    it "combines the parsed credentials with the registry type" do
      expect(serialized_credentials).to eq(
        "type" => "rubygems_server",
        "host" => "gem.fury.io",
        "token" => "${{secrets.GEMFURY}}",
      )
    end

    context "with an npm_registry" do
      before { registry.registry_type = "npm_registry" }

      before { registry.credentials = creds_hash.to_json }

      let(:creds_hash) do
        {
          "url" => "https://artifactory.acme.com/artifactory/api/npm/npm-stable-and-cache",
          "token" => "${{secrets.MY_ARTIFACTORY_TOKEN}}",
        }
      end

      it "combines the parsed credentials with the registry type" do
        expect(serialized_credentials).to eq(
          "type" => "npm_registry",
          "registry" => "artifactory.acme.com/artifactory/api/npm/npm-stable-and-cache",
          "token" => "${{secrets.MY_ARTIFACTORY_TOKEN}}",
        )
      end

      context "with Azure OIDC credentials" do
        let(:creds_hash) do
          {
            "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry",
            "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
            "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
          }
        end

        it "includes tenant-id and client-id in serialized credentials" do
          expect(serialized_credentials).to eq(
            "type" => "npm_registry",
            "registry" => "pkgs.dev.azure.com/myorg/_packaging/myfeed/npm/registry",
            "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
            "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
          )
        end
      end
    end

    context "with a nuget_feed" do
      before { registry.registry_type = "nuget_feed" }

      before { registry.credentials = creds_hash.to_json }

      context "with Azure OIDC credentials" do
        let(:creds_hash) do
          {
            "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
            "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
            "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
          }
        end

        it "includes tenant-id and client-id in serialized credentials" do
          expect(serialized_credentials).to eq(
            "type" => "nuget_feed",
            "url" => "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json",
            "tenant-id" => "${{secrets.AZURE_TENANT_ID}}",
            "client-id" => "${{secrets.AZURE_CLIENT_ID}}",
          )
        end
      end
    end

    context "with a terraform registry" do
      it "serializes credentials correctly" do
        registry = FactoryBot.build_stubbed(:registry, :terraform)

        expect(registry.serialized_credentials(include_metadata: true)).
          to eq({
                  "type" => "terraform_registry",
                  "host" => "registry.terraform.example.org",
                  "url" => "registry.terraform.example.org",
                  "token" => "${{secrets.TOKEN}}",
                })
      end
    end

    context "with a goproxy_server registry" do
      subject(:registry) { FactoryBot.build_stubbed(:registry, :goproxy_server) }

      it "serializes username/password credentials correctly" do
        expect(registry.serialized_credentials(include_metadata: true)).
          to eq({
                  "type" => "goproxy_server",
                  "url" => "https://goproxy.example.com",
                  "username" => "user@example.com",
                  "password" => "${{secrets.GOPROXY_PASSWORD}}",
                })
      end
    end
  end

  describe "#serialized_credential_metadata" do
    subject(:serialized_credential_metadata) do
      registry.serialized_credential_metadata
    end

    it "prunes out everything except the key" do
      expect(serialized_credential_metadata).to eq(
        "type" => "rubygems_server",
        "host" => "gem.fury.io"
      )
    end

    context "with replaces-base set" do
      let(:registry) do
        FactoryBot.create(:registry,
                          source: repo,
                          credentials: {
                            "url" => "gem.fury.io",
                            "token" => "${{secrets.GEMFURY}}",
                            "replaces-base" => false,
                          }.to_json)
      end

      it "keeps the replaces-base value" do
        expect(serialized_credential_metadata).to eq(
          "type" => "rubygems_server",
          "host" => "gem.fury.io",
          "replaces-base" => false,
        )
      end
    end

    context "with a hex_repository configuration" do
      let(:registry) do
        FactoryBot.create(:registry,
                          registry_type: "hex_repository",
                          source: repo,
                          credentials: {
                            "url" => "https://hex.example.com",
                            "repo" => "my_hex_repository",
                            "public-key-fingerprint" => "${{secrets.PUBLIC_KEY}}",
                            "auth-key" => "${{secrets.KEY}}",
                          }.to_json)
      end

      it "prunes out everything except the auth-key and repo" do
        expect(serialized_credential_metadata).to eq(
          "type" => "hex_repository",
          "url" => "https://hex.example.com",
          "repo" => "my_hex_repository",
          "public-key-fingerprint" => "${{secrets.PUBLIC_KEY}}",
        )
      end
    end
  end

  describe "#credentials" do
    let(:model) { FactoryBot.build(:registry) }

    it "stores the credentials plaintext" do
      model.credentials = \
        { url: "my.host", token: "${{secrets.PASSWORD}}" }.to_json
      model.save!
      expect(model.credentials).
        to eq({ url: "my.host", token: "${{secrets.PASSWORD}}" }.to_json)
    end
  end

  describe "#key" do
    subject { registry.key }

    context "with a Bundler registry" do
      let(:registry) do
        FactoryBot.build_stubbed(:registry, :bundler)
      end

      it { is_expected.to eq("gem.fury.io") }
    end

    context "with a Docker registry" do
      let(:registry) do
        FactoryBot.build_stubbed(:registry, :docker)
      end

      it { is_expected.to eq("a-host.io:5000") }
    end

    context "with a Hex registry" do
      let(:registry) do
        FactoryBot.build_stubbed(:registry,
                                 registry_type: "hex_organization",
                                 credentials: {
                                   organization: "acme",
                                   key: "${{secrets.HEX_KEY}}",
                                 }.to_json)
      end

      it { is_expected.to eq("acme") }
    end

    it "returns the url as the key for Terraform registries" do
      registry = FactoryBot.build_stubbed(:registry, :terraform)

      expect(registry.key).to eql("registry.terraform.example.org")
    end

    context "with a git_source" do
      let(:registry_url) { "github.com" }
      let(:registry) do
        FactoryBot.build_stubbed(:registry,
                                 registry_type: "git_source",
                                 credentials: {
                                   url: registry_url,
                                   username: "x-access-token",
                                   password: "${{secrets.MY_GITHUB_TOKEN}}",
                                 }.to_json)
      end

      it { is_expected.to eq("github.com") }

      context "and url with protocol" do
        let(:registry_url) { "https://github.com" }

        it { is_expected.to eq("github.com") }
      end

      context "and url with protocol and path" do
        let(:registry_url) { "https://github.com/acme" }

        it { is_expected.to eq("github.com") }
      end
    end
  end
end
