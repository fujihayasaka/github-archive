require "rails_helper"

module Ingest
  describe PackageMetadataProcessor, type: :job do
    include ActiveJob::TestHelper
    let(:config)           { Rails.application.config_for(:kafka).with_indifferent_access }
    let(:message_topic)    { config.fetch(:package_metadata_topic) }
    let(:processor) { described_class.new }
    let(:invalid_message) {
      { coordinates: { type: "maven", provider: "maven", namespace: "something", name: "random" }, license_spdx_expression: "Apache-6.6.6", uris: { repository: "https://github.com/this-is/invalid", project_website: "https://github.com/prelude/dailys", issue_tracker: "https://github.com/prelude/dailys/issues" }, release_date: Time.parse("2023-05-05 17:10:55.992771248 UTC"), score: { declared: 13, discovered: 25, consistency: 12, spdx: 4, texts: 6, total: 60 }, git_sha: "fbd5774684760fd1572bc32af18ee9f2466e8ac9", attributions: ["Copyright (c) Monalisa, 2023"] }
    }
    let(:unknown_package_manager) {
      { coordinates: { type: "commodore64", provider: "amiga", namespace: "resplendent", name: "cockroach", revision: "12.15.16" }, license_spdx_expression: "Apache-2.0", uris: { repository: "https://github.com/resplendent/cockroach", project_website: "https://github.com/resplendent/cockroach", issue_tracker: "https://github.com/resplendent/cockroach/issues" }, release_date: Time.parse("2023-05-05 17:10:55.992771248 UTC"), score: { declared: 13, discovered: 25, consistency: 12, spdx: 4, texts: 6, total: 60 }, git_sha: "fbd5774684760fd1572bc32af18ee9f2466e8ac9", attributions: ["Copyright (c) Monalisa, 2023"] }
    }
    let(:no_uris_hydro) {
      # this is pasted directly from Hydro, hence the JSON format
      event_from_json('{"coordinates":{"type":"pypi","provider":"pypi","namespace":"-","name":"mxnet","revision":"1.6.0b20200215"},"license_spdx_expression":"Apache-2.0","uris":{"repository":"","project_website":"","issue_tracker":""},"release_date":{"seconds":1683676800,"nanos":0},"score":{"total":60,"declared":30,"discovered":0,"consistency":15,"spdx":15,"texts":0},"git_sha":"","attributions":[]}')
    }
    let(:no_uris_release) {
      Packages::PackageRelease.new(
        package_manager: Types::PackageManager[:pip],
        package_name: "mxnet",
        version: "1.6.0b20200215",
        license: "Apache-2.0",
        published_at: Time.new(2023, 05, 10),
        clearly_defined_score: 60,
      )
    }
    # These are pasted directly from Hydro, hence the JSON format.
    # To get one of these payloads:
    # 1. Find a message of interest in Presto, e.g. https://data.githubapp.com/sql/share/db95be44
    # 2. Get the offset and partition
    # 3. Find the message by offset and partition in https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=package_license_gateway.clearlydefined.v0.PackageMetadata&tab=messages
    # 4. Copy-paste the JSON and pipe it through `jq -c` to get it on a single line
    # 5. Profit :)
    let(:npm_package_hydro) {
      event_from_json('{"coordinates":{"type":"npm","provider":"npmjs","namespace":"-","name":"jest-runner-eslint","revision":"0.7.6"},"license_spdx_expression":"MIT","uris":{"repository":"https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0","project_website":"https://github.com/jest-community/jest-runner-eslint","issue_tracker":"https://github.com/jest-community/jest-runner-eslint/issues"},"release_date":null,"score":{"total":77,"declared":30,"discovered":2,"consistency":15,"spdx":15,"texts":15},"git_sha":"","attributions":["Copyright (c) 2017 <rogelioguzmanh@gmail.com>"]}')
    }
    let(:go_package_hydro) {
      event_from_json('{"coordinates":{"type":"go","provider":"golang","namespace":"github.com%2fjenkinsci","name":"jenkins-operator","revision":"v0.8.0-beta2"},"license_spdx_expression":"","uris":{"repository":"https://pkg.go.dev/github.com/jenkinsci/jenkins-operator@v0.8.0-beta2","project_website":"","issue_tracker":""},"release_date":null,"score":{"total":0,"declared":0,"discovered":0,"consistency":0,"spdx":0,"texts":0},"git_sha":"","attributions":[]}')
    }
    let(:nuget_package_hydro_namespaced) {
      event_from_json('{"coordinates": {"type":"nuget","provider":"nuget","namespace":"alphaleonis","name":"alphafs","revision":"2.0.1", "url":""},"license_spdx_expression":"NOASSERTION","score":{"total":1,"declared":0,"discovered":1,"consistency":0,"spdx":0,"texts":0},"attributions":["(c) 2023 GitHub, Inc.","(c) 2008 VeriSign, Inc.","Copyright (c) 2008-2015 Peter Palotas, Jeffrey Jangli, Alexandr Normuradov","Copyright (c) 2008-2018 Peter Palotas, Jeffrey Jangli, Alexandr Normuradov"],"uris": {"repository":"https://github.com/alphaleonis/AlphaFS/tree/f19f2591da6efdade68e67731d5566a5f184038b","project_website":"","issue_tracker":"","registry":"https://nuget.org/packages/AlphaFS","version":"https://nuget.org/packages/AlphaFS/2.0.1","download":"https://nuget.org/api/v2/package/AlphaFS/2.0.1"},"release_date":{"seconds":1683676899,"nanos":0},"gitsha":""}')
    }
    let(:npm_package_attributions_hydro) {
      event_from_json('{"coordinates":{"type":"npm","provider":"npmjs","namespace":"-","name":"jest-runner-eslint","revision":"0.7.6"},"license_spdx_expression":"MIT","uris":{"repository":"https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0","project_website":"https://github.com/jest-community/jest-runner-eslint","issue_tracker":"https://github.com/jest-community/jest-runner-eslint/issues"},"release_date":null,"score":{"total":77,"declared":30,"discovered":2,"consistency":15,"spdx":15,"texts":15},"git_sha":"","attributions":["copyright anna john doe", "Copyright Anna John Doe", "Cöpyright Ånnä Jöhn Döё"]}')
    }
    let(:npm_package_release) {
      Packages::PackageRelease.new(
        package_manager: Types::PackageManager[:npm],
        package_name: "jest-runner-eslint",
        version: "0.7.6",
        source_url: "https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0",
        home_url: "https://github.com/jest-community/jest-runner-eslint",
        license: "MIT",
        clearly_defined_score: 77,
        attributions: ["Copyright (c) 2017 <rogelioguzmanh@gmail.com>"]
      )
    }
    let(:npm_package_long_license) {
      {
        coordinates: {
          type: "npm",
          provider: "npmjs",
          name: "jest-runner-eslint",
          revision: "0.7.6",
        },
        license_spdx_expression: "MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT AND MIT",
        uris: {
          repository: "https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0",
          project_website: "https://github.com/jest-community/jest-runner-eslint",
          issue_tracker: "https://github.com/jest-community/jest-runner-eslint/issues" },
        release_date: nil,
        score: {
          total: 77,
          declared: 30,
          discovered: 2,
          consistency: 15,
          spdx: 15,
          texts: 15 },
        git_sha: "",
        attributions: ["Copyright (c) 2017 <rogelioguzmanh@gmail.com>"],
     }
    }
    let(:npm_package_long_license_release) {
      Packages::PackageRelease.new(
        package_manager: Types::PackageManager[:npm],
        package_name: "jest-runner-eslint",
        version: "0.7.6",
        source_url: "https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0",
        home_url: "https://github.com/jest-community/jest-runner-eslint",
        license: "NOASSERTION",
        clearly_defined_score: 77,
        attributions: ["Copyright (c) 2017 <rogelioguzmanh@gmail.com>"]
      )
    }

    def event_from_json(json)
      e = JSON.load(json).with_indifferent_access
      e[:release_date] = Google::Protobuf::Timestamp.new(e[:release_date]) if e[:release_date].present?
      e
    end

    def process
      run_consumer(processor)
    end

    def run
      perform_enqueued_jobs do
        @last_run_result = process
      end
    end

    def publish(events)
      # prepare for the find_repo calls
      events.each do |update|
        repo_url = update.with_indifferent_access.dig(:uris, :repository)
        next unless repo_url.present? && repo_url.start_with?("http://github.com/")
        nwo = repo_url.delete_prefix("https://github.com/")
        factory.given_repository(nwo: nwo, public: true)
      end

      events.each { |update| processor.publish(update, topic: message_topic) }
    end

    before do
      processor.spec_reset
    end

    it "correctly parses a complete npm message" do
      npm_parsed = described_class.create_package_release(npm_package_hydro.with_indifferent_access)
      expect(npm_parsed).to eq(npm_package_release)
    end

    it "ignores namespaces for ecosystems without namespace support" do
      expect(described_class.create_package_release(nuget_package_hydro_namespaced.with_indifferent_access)).to eq(
        Packages::PackageRelease.new(
          package_manager: Types::PackageManager[:nuget],
          package_name: "alphafs",
          version: "2.0.1",
          source_url: "https://github.com/alphaleonis/AlphaFS/tree/f19f2591da6efdade68e67731d5566a5f184038b",
          license: "NOASSERTION",
          clearly_defined_score: 1,
          published_at: "2023-05-10 00:01:39",
          attributions: ["(c) 2023 GitHub, Inc.",
                         "(c) 2008 VeriSign, Inc.",
                         "Copyright (c) 2008-2015 Peter Palotas, Jeffrey Jangli, Alexandr Normuradov",
                         "Copyright (c) 2008-2018 Peter Palotas, Jeffrey Jangli, Alexandr Normuradov"]
        )
      )
    end

    it "correctly parses a complete go message" do
      expect(PackageMetadataProcessor.create_package_release(go_package_hydro)).to eq(Packages::PackageRelease.new(
        package_manager: Types::PackageManager[:go],
        package_name: "github.com/jenkinsci/jenkins-operator",
        version: "v0.8.0-beta2",
        namespace: "github.com%2fjenkinsci",
        source_url: nil,
        home_url: nil,
        license: "",
        clearly_defined_score: 0,
      ))
    end

    it "truncates license string if past legacy length limits, during validation" do
      parsed_release = nil
      expect {
        parsed_release = described_class.create_package_release(npm_package_long_license)
      }.to have_instrumented_increment("etl.ospo.ingest.validation_error",
                                       { reason: "license_truncated", type: "npm" })
      expect(parsed_release).to eq(npm_package_long_license_release)
    end

    it "passes the correct parsed message to LoadPackageMetadataJob" do
      expect(Failbot).to_not receive(:report)
      expect(LoadPackageMetadataJob).to receive(:perform_later).with(npm_package_release, persist_data: true)

      publish([npm_package_hydro])
      run
    end

    it "allows updates with no uris" do
      expect(Failbot).to_not receive(:report)
      expect(LoadPackageMetadataJob).to receive(:perform_later).with(no_uris_release, persist_data: true)

      publish([no_uris_hydro])
      run
    end

    it "logs validation errors and skips LoadPackageMetadataJob" do
      expect(Failbot).to receive(:report).once do |ex, context|
        expect(ex).to be_a(Ingest::OspoValidationError)
        expect(ex.message).to start_with("message was missing coordinates.revision")
        expect(Failbot.context.reduce(&:merge)).to include({ ospo_type: "maven" })
      end
      expect(LoadPackageMetadataJob).to_not receive(:perform_later)

      processor.publish(invalid_message, topic: message_topic)
      expect { run }.to change { Package.count }.by(0)
    end

    it "skips unknown package managers and stats them" do
      processor.publish(unknown_package_manager, topic: message_topic)
      expect(LoadPackageMetadataJob).to_not receive(:perform_later)
      expect(Failbot).to_not receive(:report)

      expect { run }.to have_instrumented_increment("etl.ospo.ingest.unsupported_package_manager", { type: "commodore64" })
    end

    it "has a matching PackageManager for every supported ecosystem" do
      described_class::OSPO_DG_SUPPORTED_ECOSYSTEMS.each do |ecosystem|
        package_manager = described_class.ospo_type_to_package_manager(ecosystem)
        expect(package_manager).to be_a(Types::PackageManager)
      end
    end

    it "creates releases with the correct package_name" do
      package_release = described_class.create_package_release(npm_package_hydro.with_indifferent_access)
      expect(package_release.package_name).to eq("jest-runner-eslint")

      npm_package_hydro["coordinates"]["namespace"] = "@sample-namespace"
      package_release = described_class.create_package_release(npm_package_hydro.with_indifferent_access)
      expect(package_release.package_name).to eq("@sample-namespace/jest-runner-eslint")
    end
  end
end
