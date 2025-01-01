require "rails_helper"

module Ingest
  describe RepositoryManifestFileDeletedProcessor do
    include ActiveJob::TestHelper

    let(:config)           { Rails.application.config_for(:kafka).with_indifferent_access }
    let(:message_topic)    { config.fetch(:repo_manifest_file_deleted_topic) }
    let(:processor)        { described_class.new }
    let(:github_repo_id)   { 12345 }

    let(:manifest_file1) {
      {
          filename: "Gemfile.lock",
          git_ref: "303cbb30c474646b4abe1ae74f6b3dc0e182c478",
          path: "",
          pushed_at: Time.now,
        }
    }
    let(:manifest_file2) {
      {
        filename: "pom.xml",
          git_ref: "a93c0fda97159bd491a9435c731c277f0208cdcc",
          path: "src/main/java",
          pushed_at: Time.now,
        }
    }

    let(:delete_message1) {
      {
        manifest_file: manifest_file1,
        repository_fork: false,
        repository_id: github_repo_id,
        repository_private: false
      }
    }
    let(:delete_message2) {
      {
        manifest_file: manifest_file2,
        repository_fork: true,
        repository_id: github_repo_id,
        repository_private: true
      }
    }

    it "consumes message and publishes delete manifest job" do
      processor.publish(delete_message1)
      processor.publish(delete_message2)

      run_consumer(processor)

      expect(ProcessManifestDeletedJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_deleted").exactly(2).times
    end

    it "returns github_repository_id and manifest name, path in failbot_context" do
      context = processor.get_processor_specific_logging_context(
        Hydro::Source::Message.new(
          value: {
            repository_id: github_repo_id,
            manifest_file: {
              filename: "some.filename",
              path: "src/somewhere",
            }
          }
        )
      )

      expect(context).to include({
        "gh.repo.id" => github_repo_id,
        "gh.dependency_graph.manifest.filename" => "some.filename",
        "gh.dependency_graph.manifest.path" => "src/somewhere",
      })
    end

  end
end
