# typed: true
# frozen_string_literal: true

require "test_helper"

class PorterStafftoolsClientTest < GitHub::TestCase
  setup do
    name_without_line_number = method_name.sub(/_L\d+$/, "")
    VCR.insert_cassette "porter/stafftools_client_test/#{name_without_line_number}", record: :none
    @client = Porter::StafftoolsClient.new(repository_url: "http://porter.test/whatever", internal_api_token: "APITOKEN", request_id: "github-request-id")
  end

  teardown do
    VCR.eject_cassette
  end

  context "#get_status" do
    test "porter 500s" do
      assert_nil @client.get_status
    end
    test "porter 404s" do
      assert_nil @client.get_status
    end
    test "porter responds with repository not present" do
      assert_equal [:not_found, nil], @client.get_status
    end
    test "porter responds with status" do
      assert_equal [:ok, { "status" => "the status" }], @client.get_status
    end
    test "porter responds with error status" do
      assert_equal [:ok, { "status" => "error", "failed_step" => "the step" }], @client.get_status
    end
  end
end
