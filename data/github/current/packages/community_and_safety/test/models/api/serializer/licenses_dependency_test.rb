# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class LicenseSerializersTest < Api::SerializerTestCase
  fixtures do
    @repo  = create(:repository, from_example: :license_plaintext)
  end

  setup do
    @mit = License.find("mit")
    @other = License.find("other")
    RepositoryLicense.create! repository: @repo, license_id: @mit.id
  end

  test "simple license hash" do
    output = serialized_as(:license, @mit)
    refute output["body"]
  end

  test "full license hash" do
    output = serialized_as(:license, @mit, full: true)
    assert output["body"]
  end

  test "license content hash" do
    output = serialized_as(:license_content, @repo.preferred_license, repo: @repo, full: true)
    assert output["content"]
  end

  test "psuedo licenses don't have a URL" do
    output = serialized_as(:license, @other)
    refute output["url"]
  end

  SimpleLicenseQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
      query($key : String!) {
        license(key: $key) {
          ...Api::Serializer::LicensesDependency::SimpleLicenseFragment
        }
      }
    GRAPHQL

  test "simple license graphql hash" do
    results = Api::App::PlatformClient.query(SimpleLicenseQuery, variables: { "key": @mit.key })
    output = serialized_as(:graphql_simple_license, results.data.license)
    refute output["body"]
  end
end
