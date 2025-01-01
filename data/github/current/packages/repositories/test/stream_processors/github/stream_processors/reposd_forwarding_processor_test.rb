# typed: true
# frozen_string_literal: true

require "test_helper"

module GitHub::StreamProcessors
  class ReposdForwardingProcessorTest < GitHub::TestCase
    include HydroTestHelpers

    test "it calls the reposd client correctly" do
      enable_feature_flag(:hydro_reposd_forwarding_job)

      message = {
        request_id: "123",
        method: "GET",
        route: "/repositories/:repository_id/contents/?*",
        path: "/repositories/1/contents/",
        query: "ref=master",
        request_headers: { "HTTP_ACCEPT" => "*/*" }
      }

      Repositories::ReposdClient.any_instance.expects(:api_request).with(path: "/repositories/1/contents/", params: "ref=master", headers: { "HTTP_ACCEPT" => "*/*" })

      hydro_publisher.publish(message, schema: "hydro.schemas.github.v1.ExperimentResponse", topic: "github.repos.contents.v1.ExperimentResponse")

      run_processor(GitHub::StreamProcessors::ReposdForwardingProcessor.new)
    end
  end
end
