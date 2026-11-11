# frozen_string_literal: true

require "rails_helper"
require "cgi"
require "ecosystem_file_detector"

RSpec.describe EcosystemFileDetector do
  let(:account) { create(:account) }
  let(:repo_id) { 12345 }
  let(:directory) { "." }
  let(:metric_prefix) { "consumer.test" }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:uv_lock_url) { "#{github_url}repositories/#{repo_id}/contents/uv.lock" }

  before do
    Rails.cache.clear
    allow(GitHubHelpers).to receive(:access_token_for).and_return("token")
  end

  describe ".uv_lock_exists?" do
    subject(:result) do
      described_class.send(:uv_lock_exists?,
                           account: account,
                           repo_id: repo_id,
                           directories: [directory],
                           metric_prefix: metric_prefix,)
    end

    context "when account is nil" do
      let(:account) { nil }

      it { is_expected.to be(false) }

      it "does not make any API calls" do
        result
        expect(WebMock).not_to have_requested(:get, uv_lock_url)
      end
    end

    context "when uv.lock exists in the repository root" do
      before do
        stub_request(:get, uv_lock_url).to_return(
          status: 200,
          body: { content: Base64.encode64("lockfile content") }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it { is_expected.to be(true) }

      it "emits the check metric with cached: false" do
        expect(MetricsClient).to receive(:increment).with(
          "#{metric_prefix}.uv_lock_check",
          tags: { repo_id: repo_id, cached: false }
        )
        result
      end

      it "emits the detected metric" do
        expect(MetricsClient).to receive(:increment).with(
          "#{metric_prefix}.uv_lock_detected",
          tags: { repo_id: repo_id }
        )
        result
      end

      it "caches the result using repo_id and path (no ref)" do
        result
        cache_key = "ecosystem_file_exists/#{repo_id}/uv.lock"
        expect(Rails.cache.read(cache_key)).to be(true)
      end

      it "uses the cached result on subsequent calls" do
        result # first call - populates cache

        WebMock.reset!

        # second call - should use cache without hitting the API
        expect do
          described_class.send(:uv_lock_exists?,
                               account: account,
                               repo_id: repo_id,
                               directories: [directory],
                               metric_prefix: metric_prefix,)
        end.not_to raise_error
        expect(WebMock).not_to have_requested(:get, uv_lock_url)
      end

      it "emits the check metric with cached: true on the second call" do
        result # first call - populates cache

        expect(MetricsClient).to receive(:increment).with(
          "#{metric_prefix}.uv_lock_check",
          tags: { repo_id: repo_id, cached: true }
        )
        described_class.send(:uv_lock_exists?,
                             account: account,
                             repo_id: repo_id,
                             directories: [directory],
                             metric_prefix: metric_prefix,)
      end
    end

    context "when a ref is specified" do
      subject(:result) do
        described_class.send(:uv_lock_exists?,
                             account: account,
                             repo_id: repo_id,
                             directories: [directory],
                             ref: ref,
                             metric_prefix: metric_prefix,)
      end

      let(:ref) { "refs/heads/main" }
      let(:uv_lock_url_with_ref) { "#{github_url}repositories/#{repo_id}/contents/uv.lock?ref=#{CGI.escape(ref)}" }

      before do
        stub_request(:get, uv_lock_url_with_ref).to_return(
          status: 200,
          body: { content: Base64.encode64("lockfile content") }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it { is_expected.to be(true) }

      it "includes the ref in the cache key" do
        result
        cache_key = "ecosystem_file_exists/#{repo_id}/#{ref}/uv.lock"
        expect(Rails.cache.read(cache_key)).to be(true)
      end

      it "does not mix cache with the no-ref lookup" do
        result
        no_ref_cache_key = "ecosystem_file_exists/#{repo_id}/uv.lock"
        expect(Rails.cache.read(no_ref_cache_key)).to be_nil
      end
    end

    context "when uv.lock is in a subdirectory" do
      let(:directory) { "packages/backend" }
      let(:uv_lock_url) { "#{github_url}repositories/#{repo_id}/contents/packages/backend/uv.lock" }

      before do
        stub_request(:get, uv_lock_url).to_return(
          status: 200,
          body: { content: Base64.encode64("lockfile content") }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it { is_expected.to be(true) }

      it "uses the correct cache key" do
        result
        cache_key = "ecosystem_file_exists/#{repo_id}/packages/backend/uv.lock"
        expect(Rails.cache.read(cache_key)).to be(true)
      end
    end

    context "when uv.lock is in a directory with leading ./" do
      let(:directory) { "./myapp" }
      let(:uv_lock_url) { "#{github_url}repositories/#{repo_id}/contents/myapp/uv.lock" }

      before do
        stub_request(:get, uv_lock_url).to_return(
          status: 200,
          body: { content: Base64.encode64("lockfile content") }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it { is_expected.to be(true) }

      it "strips the leading ./ from the path" do
        result
        cache_key = "ecosystem_file_exists/#{repo_id}/myapp/uv.lock"
        expect(Rails.cache.read(cache_key)).to be(true)
      end
    end

    context "when uv.lock does not exist" do
      before do
        stub_request(:get, uv_lock_url).to_return(
          status: 404,
          body: { message: "Not Found" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it { is_expected.to be(false) }

      it "emits the not_found metric" do
        expect(MetricsClient).to receive(:increment).with(
          "#{metric_prefix}.uv_lock_not_found",
          tags: { repo_id: repo_id }
        )
        result
      end
    end

    context "when the API call fails with a standard error" do
      before do
        stub_request(:get, uv_lock_url).to_return(status: 500)
      end

      it { is_expected.to be(false) }

      it "emits the error metric" do
        expect(MetricsClient).to receive(:increment).with(
          "#{metric_prefix}.uv_lock_check_error",
          tags: { repo_id: repo_id }
        )
        result
      end

      it "logs a warning" do
        expect(Dependabot::Logger).to receive(:warn).with(
          hash_including(
            msg: "Failed to check for uv.lock",
            "gh.repo.id": repo_id,
          )
        )
        result
      end
    end

    context "when using the default metric prefix" do
      subject(:result) do
        described_class.send(:uv_lock_exists?,
                             account: account,
                             repo_id: repo_id,
                             directories: [directory],)
      end

      before do
        stub_request(:get, uv_lock_url).to_return(
          status: 200,
          body: { content: Base64.encode64("lockfile content") }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "emits metrics with the default prefix" do
        expect(MetricsClient).to receive(:increment).with(
          "uv_lock_check.uv_lock_check",
          tags: { repo_id: repo_id, cached: false }
        )
        expect(MetricsClient).to receive(:increment).with(
          "uv_lock_check.uv_lock_detected",
          tags: { repo_id: repo_id }
        )
        result
      end
    end
  end

  describe ".resolve_package_manager" do
    subject(:result) do
      described_class.resolve_package_manager(
        package_manager: package_manager,
        account: account,
        repo_id: repo_id,
        directories: directories,
        manifest_name: manifest_name,
        metric_prefix: metric_prefix,
      )
    end

    let(:directories) { [directory] }
    let(:manifest_name) { nil }

    context "when package manager is not maven or pip" do
      let(:package_manager) { PackageManagers::GO_MODULES }

      it "returns the package manager unchanged" do
        expect(result).to eq(PackageManagers::GO_MODULES)
      end

      it "does not make any API calls" do
        expect(described_class).not_to receive(:uv_lock_exists?)
        result
      end
    end

    context "when package manager is maven" do
      let(:package_manager) { PackageManagers::MAVEN }

      context "when manifest_name is nil" do
        it { is_expected.to eq(PackageManagers::MAVEN) }
      end

      context "when manifest_name is build.gradle" do
        let(:manifest_name) { "build.gradle" }

        it { is_expected.to eq(PackageManagers::GRADLE) }
      end

      context "when manifest_name is build.gradle.kts" do
        let(:manifest_name) { "build.gradle.kts" }

        it { is_expected.to eq(PackageManagers::GRADLE) }
      end

      context "when manifest_name is settings.gradle" do
        let(:manifest_name) { "settings.gradle" }

        it { is_expected.to eq(PackageManagers::GRADLE) }
      end

      context "when manifest_name is settings.gradle.kts" do
        let(:manifest_name) { "settings.gradle.kts" }

        it { is_expected.to eq(PackageManagers::GRADLE) }
      end
    end

    context "when package manager is pip" do
      let(:package_manager) { PackageManagers::PIP }
      let(:uv_lock_url) { "#{github_url}repositories/#{repo_id}/contents/uv.lock" }

      context "when manifest_name is environment.yml" do
        let(:manifest_name) { "environment.yml" }

        it { is_expected.to eq(PackageManagers::CONDA) }
      end

      context "when manifest_name is environment.yaml" do
        let(:manifest_name) { "environment.yaml" }

        it { is_expected.to eq(PackageManagers::CONDA) }
      end

      context "when manifest_name is uv.lock" do
        let(:manifest_name) { "uv.lock" }

        it { is_expected.to eq(PackageManagers::UV) }

        it "does not call uv_lock_exists? when manifest_name matches" do
          expect(described_class).not_to receive(:uv_lock_exists?)
          result
        end
      end

      context "when uv.lock exists in the repository" do
        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 200,
            body: { content: Base64.encode64("lockfile content") }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it { is_expected.to eq(PackageManagers::UV) }

        it "caches the result" do
          result
          cache_key = "ecosystem_file_exists/#{repo_id}/uv.lock"
          expect(Rails.cache.read(cache_key)).to be(true)
        end
      end

      context "when no uv.lock file is detected" do
        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 404,
            body: { message: "Not Found" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it { is_expected.to eq(PackageManagers::PIP) }
      end

      context "when account is nil" do
        let(:account) { nil }

        it { is_expected.to eq(PackageManagers::PIP) }

        it "does not make any API calls" do
          result
          expect(WebMock).not_to have_requested(:get, /repositories/)
        end
      end

      context "when uv.lock is detected in any of multiple directories" do
        let(:directories) { [".", "subproject"] }
        let(:uv_lock_url_root) { "#{github_url}repositories/#{repo_id}/contents/uv.lock" }
        let(:uv_lock_url_subproject) do
          "#{github_url}repositories/#{repo_id}/contents/subproject/uv.lock"
        end

        before do
          stub_request(:get, uv_lock_url_root).to_return(
            status: 404,
            body: { message: "Not Found" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
          stub_request(:get, uv_lock_url_subproject).to_return(
            status: 200,
            body: { content: Base64.encode64("lockfile content") }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it { is_expected.to eq(PackageManagers::UV) }
      end
    end
  end
end
