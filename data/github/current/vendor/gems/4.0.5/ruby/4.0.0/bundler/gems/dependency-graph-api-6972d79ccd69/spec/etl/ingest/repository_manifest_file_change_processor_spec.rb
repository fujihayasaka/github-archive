require "rails_helper"
require "db_helpers"
require_relative "../../support/blob_operations_responses_helper"

module Ingest
  describe RepositoryManifestFileChangeProcessor do
    include ActiveJob::TestHelper

    let(:config)           { Rails.application.config_for(:kafka).with_indifferent_access }
    let(:message_topic)    { config.fetch(:repo_manifest_file_change_topic) }
    let(:processor) { described_class.new }
    let(:manifest_file_changes) { [] }

    before do
      processor.spec_reset
    end

    it "enqueues ProcessManifestJob into ecosystem-specific queues" do
      processor.publish({
        manifest_file: {
          filename: "Gemfile",
          path: "Gemfile",
          git_ref: "2c3ed2",
          pushed_at: Time.new(2021, 04, 01).to_i,
          blob_oid: "abcde123456"
        },
        repository_id: 600,
        owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 1301,
        repository_private: false,
        repository_fork: false,
        is_backfill: false
      }, topic: message_topic)

      processor.publish({
        "repository_id": 5141,
        "repository_private": false,
        "repository_fork": false,
        "manifest_file": {
          "filename": "Gemfile",
          "path": "/src/Gemfile",
          "git_ref": "a03a7e5040612362f2f9f81e5b611016c16b",
          "pushed_at": Time.new(2021, 04, 16).to_i,
          "blob_oid": "123456abcde",
        },
        "repository_nwo": "carlsagan/thecosmos",
        "repository_stargazer_count": 999,
        "owner_id": 231,
        "is_backfill": false
      }, topic: message_topic)

      processor.publish({
        manifest_file: {
          filename: "pom.xml",
          path: "",
          git_ref: "afec2s",
          pushed_at: Time.new(2021, 04, 01).to_i
        },
        repository_id: 200,
        owner_id: 300,
        repository_nwo: "a/javaproject",
        repository_stargazer_count: 100,
        repository_private: false,
        repository_fork: false,
        is_backfill: false
      }, topic: message_topic)

      run_consumer(processor)

      expect(ProcessManifestJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_rubygems").exactly(2).times
      expect(ProcessManifestJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_maven").exactly(1).times
    end

    it "returns github_repository_id and manifest name in failbot_context" do
      context = processor.get_processor_specific_logging_context(
        Hydro::Source::Message.new(
          value: {
            repository_id: 12345,
            manifest_file: {
              filename: "some.filename"
            }
          }
        )
      )

      expect(context).to include({
        "gh.repo.id" => 12345,
        "gh.dependency_graph.manifest.filename" => "some.filename"
      })
    end
  end
end
