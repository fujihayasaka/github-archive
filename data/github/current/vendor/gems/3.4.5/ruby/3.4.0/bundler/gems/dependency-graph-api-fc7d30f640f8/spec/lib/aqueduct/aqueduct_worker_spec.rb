# frozen_string_literal: true

require "rails_helper"

require "aqueduct"
require "aqueduct/test_helpers/test_server"
require "webrick"

require_relative "../../../lib/aqueduct/aqueduct_worker"

describe DependencyGraph::Aqueduct::Worker do
  let(:server_port) { 62345 }
  let(:aqueduct_client) { Aqueduct::Client.new(app: "dependency-graph-api", url: "http://127.0.0.1:#{server_port}/twirp") }
  let(:worker) { described_class.new(client: aqueduct_client) }
  let(:repo_id) { 1337 }

  before(:each) do
    Repository.create!(github_repository_id: 1337, public: false)
    factory do
      given_manifest(
        github_repo_id: 1337,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 5.0.0",
          },
        ]
      )
    end

    allow_any_instance_of(WEBrick::HTTPServer).to receive(:access_log)
  end

  context "#start" do
    it "works a job" do
      expect(Repository.where(github_repository_id: repo_id).first.manifests).to_not be_empty

      # Start the Aqueduct test server
      Aqueduct::TestHelpers::TestServer.run(port: server_port, logger: Rails.logger) do |handler|

        # start the worker thread
        t_worker = Thread.new { worker.start }

        # enqueue a job
        aqueduct_client.send_job(
          headers: {},
          payload: {
            arguments: [repo_id],
            job_class: "ClearDependenciesJob",
            queue_name: "service-to-service",
          }.to_json,
          queue: "service-to-service",
          redelivery_timeout_secs: 1,
        )

        # sleep for a very short amount of time to ensure the job is picked up
        sleep 0.05

        # While this certainly has all the hallmarks of a flaky test,
        # it seems like the test server and the worker work fast enough
        # that it isn't a problem. It might be necessary to tune the
        # sleep value above and/or introduce some kind of dynamic retry in the future.

      ensure
        # stop the worker, which finishes the job if it's still processing
        worker.stop
        t_worker.join
      end

      expect(Repository.where(github_repository_id: repo_id).first.manifests).to be_empty
    end
  end
end
