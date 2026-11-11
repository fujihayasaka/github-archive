require "rails_helper"
require "climate_control"

module Ingest
  describe Clearlydefined do
    # let(:logger_double) { instance_double(Logger) }
    let(:logger_double) { spy("Logger") }

    before do
      allow(DependencyGraph).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:error)
      allow(logger_double).to receive(:debug)
      RSpec::Mocks.configuration.verify_partial_doubles = false
    end

    describe Ingest::Clearlydefined::Config do
      it "initializes with default values" do
        ClimateControl.modify(
          CLEARLYDEFINED_HARVESTER_HOST: nil,
          CLEARLYDEFINED_HARVESTER_AUTH_TOKEN: nil,
          CLEARLYDEFINED_HARVESTER_ENABLED: nil
        ) do
          config = Ingest::Clearlydefined::Config.new

          expect(config.harvester_host).to eq("https://ospo-clearlydefined-harvester-gh-staging.service.iad.github.net")
          expect(config.harvester_auth_token).to be_nil
          expect(config.harvester_enabled).to be false
        end
      end
      it "reads environment variables" do
        ClimateControl.modify(
          CLEARLYDEFINED_HARVESTER_HOST: "other-host",
          CLEARLYDEFINED_HARVESTER_AUTH_TOKEN: "token",
          CLEARLYDEFINED_HARVESTER_ENABLED: "true"
        ) do
          config = Ingest::Clearlydefined::Config.new

          expect(config.harvester_host).to eq("other-host")
          expect(config.harvester_auth_token).to eq("token")
          expect(config.harvester_enabled).to be true
        end
      end
    end

    describe Ingest::Clearlydefined::Harvester do
      describe "#harvest" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }

        it "returns false if the payload is nil" do
          allow(harvester).to receive(:get_harvester_payload).with(any_args).and_return(nil)
          expect(harvester.harvest(Types::PackageManager::ACTIONS, "test/1.0.0")).to be false
          expect(logger_double).not_to have_received(:error)
        end

        it "returns false if the request fails" do
          allow(harvester).to receive(:get_harvester_payload).with(any_args).and_return("test")
          allow(harvester).to receive(:send_harvest_request).with(any_args).and_return(false)
          expect(harvester.harvest(Types::PackageManager::ACTIONS, "test/1.0.0")).to be false
          expect(logger_double).to have_received(:error).with(
            "Failed to send harvest request with payload test",
            "gh.job.name" => "package_loader")
        end
      end
      describe "#send_harvest_request" do
        require "webmock/rspec"
        let(:config) do
          ClimateControl.modify(
            CLEARLYDEFINED_HARVESTER_AUTH_TOKEN: "token",
          ) do
            Ingest::Clearlydefined::Config.new
          end
        end
        let(:harvester) { described_class.new(config) }
        let(:request_payload) do
          { package_manager: Types::PackageManager::NPM, package_with_version: "lodash/4.17.21" }
        end

        before do
          WebMock.disable_net_connect!(allow_localhost: true)
        end

        after do
          WebMock.allow_net_connect!
        end

        it "returns true if the request is successful" do
          stub_request(:post, "https://ospo-clearlydefined-harvester-gh-staging.service.iad.github.net/requests")
            .to_return(status: 201, body: "", headers: {})
          expect(harvester.send_harvest_request({})).to be true
          expect(logger_double).not_to have_received(:error)
        end

        it "returns false if the request fails" do
          stub_request(:post, "https://ospo-clearlydefined-harvester-gh-staging.service.iad.github.net/requests")
            .to_return(status: 500, body: "", headers: {})
          expect(harvester.send_harvest_request(request_payload)).to be false
          expect(logger_double).to have_received(:error).with(
            "Harvester request failed: 500, body: ",
            "gh.job.name" => "package_loader")
        end
      end

      describe "#get_harvester_payload" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }

        it "handles unsupported package managers" do
          expect(harvester.get_harvester_payload(Types::PackageManager::ACTIONS, "test/1.0.0")).to be_nil
          expect(logger_double).not_to have_received(:error)
          expect(harvester.get_harvester_payload(Types::PackageManager::SWIFT, "test/1.0.0")).to be_nil
          expect(logger_double).not_to have_received(:error)
          expect(harvester.get_harvester_payload(Types::PackageManager::PUB, "test/1.0.0")).to be_nil
          expect(logger_double).not_to have_received(:error)
        end

        it "returns nil for unknown package managers" do
          allow(harvester).to receive(:get_harvester_payload).with(any_args).and_call_original
          expect(harvester.get_harvester_payload(Types::PackageManager::UNKNOWN, "test/1.0.0")).to be_nil
          expect(logger_double).to have_received(:error).with(
            "Package manager 'unknown' is UNKNOWN.",
            "gh.job.name" => "package_loader"
          )
        end

      end

      describe "#convert_to_maven_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          describe "#convert_to_maven_coordinates" do

            it "handles standard maven packages" do
              package_version = "org.springframework:spring-core/5.0.0"
              expect(harvester.convert_to_maven_coordinates(package_version))
                .to eq("maven/mavencentral/org.springframework/spring-core/5.0.0")
            end

            it "detects android packages" do
              package_version = "com.android.tools:sdk/3.0.0"
              expect(harvester.convert_to_maven_coordinates(package_version))
                .to eq("maven/mavengoogle/com.android.tools/sdk/3.0.0")
            end

            it "detects gradle plugins" do
              package_version = "org.example:gradle-build-tools/2.0.0"
              expect(harvester.convert_to_maven_coordinates(package_version))
                .to eq("maven/gradleplugin/org.example/gradle-build-tools/2.0.0")
            end
          end
        end

        context "with invalid input" do
          it "handles invalid namespace format" do
            package_version = "org.springframework.spring-core/5.0.0"
            expect(harvester.convert_to_maven_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid maven namespace + package_name: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end

          it "handles invalid version format" do
            package_version = "org.springframework:spring-core:5.0.0"
            expect(harvester.convert_to_maven_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid maven package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_nuget_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard nuget packages" do
            package_version = "Newtonsoft.Json/13.0.1"
            expect(harvester.convert_to_nuget_coordinates(package_version))
              .to eq("nuget/nuget/-/Newtonsoft.Json/13.0.1")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "Newtonsoft.Json:13.0.1"
            expect(harvester.convert_to_nuget_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid nuget package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_composer_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard composer packages" do
            package_version = "symfony/console/5.4.0"
            expect(harvester.convert_to_composer_coordinates(package_version))
              .to eq("composer/packagist/symfony/console/5.4.0")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "symfony/console:5.4.0"
            expect(harvester.convert_to_composer_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid composer package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_go_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard go packages" do
            package_version = "github.com/gorilla/mux/v1.8.0"
            expect(harvester.convert_to_go_coordinates(package_version))
              .to eq("go/golang/github.com%2fgorilla/mux/v1.8.0")
          end

          it "handles go packages with multiple parts in the namespace" do
            package_version = "github.com/gorilla/mux/v2/v2.8.0"
            expect(harvester.convert_to_go_coordinates(package_version))
              .to eq("go/golang/github.com%2fgorilla%2fmux/v2/v2.8.0")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "github.com/gorilla:v2.8.0"
            expect(harvester.convert_to_go_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid gomod package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_rust_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard rust packages" do
            package_version = "rand/0.8.4"
            expect(harvester.convert_to_rust_coordinates(package_version))
              .to eq("crate/cratesio/-/rand/0.8.4")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "rand:0.8.4"
            expect(harvester.convert_to_rust_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid rust package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_ruby_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard ruby packages" do
            package_version = "rails/6.1.4"
            expect(harvester.convert_to_rubygems_coordinates(package_version))
              .to eq("gem/rubygems/-/rails/6.1.4")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "rails:6.1.4"
            expect(harvester.convert_to_rubygems_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid rubygems package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_pypi_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard pypi packages" do
            package_version = "requests/2.26.0"
            expect(harvester.convert_to_pypi_coordinates(package_version))
              .to eq("pypi/pypi/-/requests/2.26.0")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "requests:2.26.0"
            expect(harvester.convert_to_pypi_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid pip package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end

      describe "#convert_to_npm_coordinates" do
        let(:config) { Ingest::Clearlydefined::Config.new }
        let(:harvester) { described_class.new(config) }
        context "with valid input" do
          it "handles standard npm packages" do
            package_version = "lodash/4.17.21"
            expect(harvester.convert_to_npm_coordinates(package_version))
              .to eq("npm/npmjs/-/lodash/4.17.21")
          end

          it "handles namespaced npm packages" do
            package_version = "@angular/core/13.0.0"
            expect(harvester.convert_to_npm_coordinates(package_version))
              .to eq("npm/npmjs/@angular/core/13.0.0")
          end

          it "handles namespaced npm packages with multiple parts in the namespace" do
            package_version = "@angular/material/13.0.0"
            expect(harvester.convert_to_npm_coordinates(package_version))
              .to eq("npm/npmjs/@angular/material/13.0.0")
          end
        end

        context "with invalid input" do
          it "handles invalid version format" do
            package_version = "lodash:4.17.21"
            expect(harvester.convert_to_npm_coordinates(package_version)).to be_nil
            expect(logger_double).to have_received(:error).with(
              "******** Invalid npm package-version: #{package_version}",
              "gh.job.name" => "package_loader"
            )
          end
        end
      end
    end
  end
end
