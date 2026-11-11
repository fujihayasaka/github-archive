# frozen_string_literal: true

require "test_helper"

class DependencyGraphControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "fetches repo info from the DG API client" do
    client = mock("DependencyGraph::Client")
    client.expects(:get_package_repo)
      .with(package_manager: :RUBYGEMS, package_name: "rails")
      .returns("rails/rails")
    DependencyGraph::Client.stubs(:new).returns(client)

    get package_repo_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "rubygems", package_name: "rails" }

    assert_response :ok
    data = response.parsed_body
    assert_equal "rails/rails", data["repo_nwo"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "returns nil repo_nwo if DG API does not return any package repo" do
    DependencyGraph::Client.any_instance.stubs(:get_package_repo).returns(nil)

    get package_repo_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "rubygems", package_name: "rails" }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["repo_nwo"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "fetches estimated impact info from the DG API client" do
    client = mock("DependencyGraph::Client")
    client.expects(:get_estimated_impact)
      .with(
        package_manager: :RUBYGEMS,
        package_name: "rails",
        version_range: "> 1.0.0",
      )
      .returns(99)
    DependencyGraph::Client.stubs(:new).returns(client)

    get estimated_impact_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: {
        ecosystem: "rubygems",
        package_name: "rails",
        version_range: "> 1.0.0",
      }

    assert_response :ok
    data = response.parsed_body
    assert_equal 99, data["impact"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "returns nil impact if DG API does not return an estimated impact" do
    DependencyGraph::Client.any_instance.stubs(:get_estimated_impact).returns(nil)

    get estimated_impact_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: {
        ecosystem: "rubygems",
        package_name: "rails",
        version_range: "> 1.0.0",
      }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["impact"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "returns an error when a QueryError exception is raised" do
    api_response = stub(
      status: 400,
      body: { errors: [{ message: "Unauthorized" }] },
    )
    exception = DependencyGraph::Client::QueryError.new("Test error", response: api_response)
    DependencyGraph::Client.any_instance.stubs(:get_estimated_impact).raises(exception)

    get estimated_impact_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: {
        ecosystem: "rubygems",
        package_name: "rails",
        version_range: "> 1.0.0",
      }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["impact"]
    assert_equal 400, data["status"]
    assert_equal "Unauthorized", data["error"]
  end

  test "returns an error when an ecosystem is given but unmappable" do
    get estimated_impact_dependency_graph_path,
      headers: { "X-Okta-Username" => @user.email },
      params: {
        ecosystem: "i-am-unmappable!",
        package_name: "rails",
        version_range: "> 1.0.0",
      }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["impact"]
    assert_equal 200, data["status"]
    assert_equal "Unsupported ecosystem", data["error"]
  end
end
