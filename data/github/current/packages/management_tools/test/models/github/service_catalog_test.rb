# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubServiceCatalogTest < GitHub::TestCase
  setup do
    ENV["SERVICE_CATALOG_TOKEN"] = "foo"
  end

  teardown do
    ENV.delete("SERVICE_CATALOG_TOKEN")
  end

  test "sends search query to Service Catalog" do
    assert_predicate GitHub::ServiceCatalog, :enabled?

    with_all_http_requests_disabled do
      variables = {
        "filterSelection" => { "query" => "features" },
        "after" => nil,
      }
      payload = {
        query: ServiceCatalog::Client::Services::ListServicesQuery.build_query(
          variables,
          service_detail_fragment: GitHub::ServiceCatalog::SERVICE_NAMES_FRAGMENT
        ),
        variables: variables,
      }
      assert_match(/ServiceFilterSelectionInput/, payload[:query])

      response = {
        data: { services: { totalCount: 1, edges: [
          {
            node: {
              name: "github/features"
            },
            cursor: "MtA",
          }
        ] } }
      }
      stub_req = stub_request(:post, GitHub::ServiceCatalog::STAGING_ENDPOINT).
        with(body: JSON.generate(payload)).
        to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(response))

      services = GitHub::ServiceCatalog.find_services_by_name(name: "features")
      assert_equal ["github/features"], services.map(&:name)

      assert_requested(stub_req)
    end
  end
end
