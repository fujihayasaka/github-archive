# frozen_string_literal: true

require "rails_helper"

RSpec.describe "UV Security Advisory Integration", type: :integration do
  describe "end-to-end uv security advisory flow" do
    let(:repo) { create(:repo) }
    let(:fixture_name) { "push_pip_on_uv_lock" }
    let(:hydro_payload) do
      hydro_fixture(
        name: fixture_name,
        schema: "github.v1.RepositoryVulnerabilityAlertCreate"
      )
    end

    let(:message) do
      instance_double(
        Hydro::Consumer::ConsumerMessage,
        value: hydro_payload,
        timestamp: Time.now.utc,
        headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
      )
    end

    let(:user) do
      HydroHandlers::GitHub::User.from_message(message)
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(user.id),
        enabled: false
      )
      allow(Repo).to receive_messages(find_by: repo, exists?: true)
      allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).and_return(
        build_stubbed(:advisories_response, name: "requests", ecosystem: "ECOSYSTEM_PIP")
      )
    end

    it "creates a uv security update job for uv.lock" do
      expect do
        VulnerabilityAlertHandler.run(message)
      end.to change(UpdateConfig, :count).by(1).
        and have_enqueued_job(CreateSecurityUpdateJob).with(
          hash_including(
            dependencies: ["requests"]
          )
        )

      update_config = UpdateConfig.last
      expect(update_config.package_manager).to eq("uv")
    end

    # Test regular pip flow still works
    context "with requirements.txt file" do
      let(:fixture_name) { "push_pip_on_requirements_txt" }

      it "creates a pip security update job" do
        expect do
          VulnerabilityAlertHandler.run(message)
        end.to change(UpdateConfig, :count).by(1).
          and have_enqueued_job(CreateSecurityUpdateJob)

        update_config = UpdateConfig.last
        expect(update_config.package_manager).to eq("pip")
      end
    end
  end

  describe "version updates preservation for uv" do
    let(:uv_config) { create(:update_config, package_manager: "uv") }

    it "preserves UV ecosystem for version updates" do
      expect(Advisorydb.to_advisorydb_ecosystem(PackageManagers::UV)).
        to eq(:ECOSYSTEM_UV)
    end

    it "does not interfere with existing UV version update flow" do
      # Test that version updates still use the UV ecosystem directly
      create(:update_job, update_config: uv_config, dependencies: ["requests"])

      # Mock the advisory client to verify ecosystem used
      allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories) do |input|
        # For version updates, this should be called with ECOSYSTEM_UV
        # But for security updates, it should be called with ECOSYSTEM_PIP
        expect(input[:packages].first[:ecosystem]).to eq(:ECOSYSTEM_UV)
        build_stubbed(:advisories_response, ecosystem: "ECOSYSTEM_UV")
      end

      # This would normally be called during version updates, not security updates
      # But we're testing that the direct ecosystem mapping still works
      GitHubSecurityAdvisory.fetch(PackageManagers::UV, ["requests"])
    end
  end

  describe "security vs version update flows" do
    let(:uv_config) { create(:update_config, package_manager: "uv") }
    let(:pip_advisories_response) do
      build_stubbed(:advisories_response, name: "requests", ecosystem: "ECOSYSTEM_PIP")
    end

    it "uses PIP ecosystem for UV security updates" do
      # Create a security update job for UV package manager
      job = create(:update_job, :security, update_config: uv_config, dependencies: ["requests"])

      # Mock the advisory client and verify it receives PIP ecosystem
      allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories) do |input|
        expect(input[:packages].first[:ecosystem]).to eq(:ECOSYSTEM_PIP)
        pip_advisories_response
      end

      # Trigger the advisory lookup - this should use PIP ecosystem due to ADVISORY_NORMALIZATION_MAPPING
      advisories = job.relevant_security_advisories_hash

      expect(advisories).not_to be_empty
      expect(advisories.first[:dependency_name]).to eq("requests")
    end

    it "uses UV ecosystem for version updates" do
      # For version updates, the ecosystem should remain UV
      expect(Advisorydb.to_advisorydb_ecosystem(PackageManagers::UV)).to eq(:ECOSYSTEM_UV)

      # Create a version update job (not security)
      create(:update_job, update_config: uv_config, dependencies: ["requests"], security_updates_only: false)

      # Mock to verify ecosystem used for version update advisory lookup
      allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories) do |input|
        expect(input[:packages].first[:ecosystem]).to eq(:ECOSYSTEM_UV)
        build_stubbed(:advisories_response, name: "requests", ecosystem: "ECOSYSTEM_UV")
      end

      GitHubSecurityAdvisory.fetch(PackageManagers::UV, ["requests"])
    end
  end

  describe "edge cases and regression tests" do
    context "mixed Python projects" do
      let(:repo) { create(:repo) }
      let(:message) do
        instance_double(
          Hydro::Consumer::ConsumerMessage,
          value: hydro_payload,
          timestamp: Time.now.utc,
          headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
        )
      end
      let(:user) do
        HydroHandlers::GitHub::User.from_message(message)
      end

      before do
        stub_monolith_feature(
          :dependabot_global_app_onboarding,
          actor: FeatureFlags::Actor::User.new(user.id),
          enabled: false
        )
        allow(Repo).to receive_messages(find_by: repo, exists?: true)
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).and_return(
          build_stubbed(:advisories_response, name: "requests", ecosystem: "ECOSYSTEM_PIP")
        )
      end

      context "with a uv.lock file" do
        let(:hydro_payload) do
          hydro_fixture(
            name: "push_pip_on_uv_lock",
            schema: "github.v1.RepositoryVulnerabilityAlertCreate"
          )
        end

        it "creates UV update config" do
          VulnerabilityAlertHandler.run(message)

          expect(UpdateConfig.last.package_manager).to eq("uv")
        end
      end

      context "with a requirements.txt file" do
        let(:hydro_payload) do
          hydro_fixture(
            name: "push_pip_on_requirements_txt",
            schema: "github.v1.RepositoryVulnerabilityAlertCreate"
          )
        end

        it "creates pip update config" do
          VulnerabilityAlertHandler.run(message)

          expect(UpdateConfig.last.package_manager).to eq("pip")
        end
      end
    end

    context "compatibility with conda" do
      it "uv and conda can coexist with pip advisories" do
        # Both UV and Conda use pip advisories for security updates
        # This test confirms they don't interfere with each other
        expect(UpdateJob::ADVISORY_NORMALIZATION_MAPPING[PackageManagers::UV]).to eq(PackageManagers::PIP)
        expect(UpdateJob::ADVISORY_NORMALIZATION_MAPPING[PackageManagers::CONDA]).to eq(PackageManagers::PIP)
      end
    end
  end
end
