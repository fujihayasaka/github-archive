# frozen_string_literal: true

require "test_helper"

class CVEAPIClientTest < ActiveSupport::TestCase
  base_url = AdvisoryDB.cve_services_api_url

  test "create_cve" do
    cve_id = "CVE-2022-20001"
    cve_json_string = load_cve_fixture(cve_id)
    cna_json_string = JSON.generate({
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    })
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has been reserved
    VCR.use_cassette("cve_api_create_cve") do
      cve_api_client.create_cve(cve_id, cna_json_string)
    end

    WebMock.assert_requested(
      :post,
      "#{base_url}/api/cve/#{cve_id}/cna",
      headers: {
        "Content-Type" => "application/json",
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      body: cna_json_string,
      times: 1,
    )
  end

  test "create_cve returns the CVE JSON hash on a successful response" do
    cve_id = "CVE-2022-20001"
    cve_json_string = load_cve_fixture(cve_id)
    cna_json_string = JSON.generate({
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    })
    cve_api_client = CVEAPI::Client.new
    # assuming the CVE has been reserved
    VCR.use_cassette("cve_api_create_cve") do
      cve_hash = cve_api_client.create_cve(cve_id, cna_json_string)
      assert cve_hash["containers"]
    end
  end

  test "create_cve raises an exception on an unsuccessful response" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_create_cve_unsuccessful") do
      error = assert_raises(CVEAPI::Client::CVEAPIClientError) do
        cve_api_client.create_cve("CVE-2022-1234", {})
      end
      assert JSON.parse(error.message)["error"]
    end
  end

  test "get_cve" do
    cve_api_client = CVEAPI::Client.new

    cve_record = VCR.use_cassette("cve_api_get_cve") do
      cve_api_client.get_cve("CVE-1999-0010")
    end

    refute_nil cve_record["containers"]["cna"]
    refute_nil cve_record["containers"]["cna"]["affected"]
    refute_nil cve_record["containers"]["cna"]["descriptions"]
    refute_nil cve_record["containers"]["cna"]["problemTypes"]
    refute_nil cve_record["containers"]["cna"]["providerMetadata"]
    refute_nil cve_record["containers"]["cna"]["references"]
    assert_equal "CVE-1999-0010", cve_record["cveMetadata"]["cveId"]
    assert_equal "PUBLISHED", cve_record["cveMetadata"]["state"]

    WebMock.assert_requested(
      :get,
      "#{base_url}/api/cve/CVE-1999-0010",
      headers: {
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      times: 1,
    )
  end

  test "get_org_quota" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_get_org_quota") do
      quota_hash = cve_api_client.get_org_quota
      assert quota_hash["id_quota"]
      assert quota_hash["total_reserved"]
      assert quota_hash["available"]
    end

    WebMock.assert_requested(
      :get,
      "#{base_url}/api/org/#{AdvisoryDB.cve_api_org}/id_quota",
      headers: {
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      times: 1,
    )
  end

  test "get_org_quota raises an exception on an unsuccessful response" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_get_org_quota_unsuccessful") do
      error = assert_raises(CVEAPI::Client::CVEAPIClientError) do
        cve_api_client.get_org_quota
      end
      assert JSON.parse(error.message)["error"]
    end
  end

  test "reject_cve" do
    cve_id = "CVE-2022-20001"
    cna_json_string = JSON.generate({
      cnaContainer: {
        rejectedReasons: [
          {
            lang: "en",
            value: "the reason",
          },
        ],
      },
    })
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has been published
    VCR.use_cassette("cve_api_reject_published_cve") do
      cve_api_client.reject_cve(cve_id, rejected_reasons: ["the reason"])
    end

    WebMock.assert_requested(
      :put,
      "#{base_url}/api/cve/#{cve_id}/reject",
      headers: {
        "Content-Type" => "application/json",
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      body: cna_json_string,
      times: 1,
    )
  end

  test "reject_cve requires rejected_reasons" do
    cve_api_client = CVEAPI::Client.new

    assert_raises(ArgumentError) do
      cve_api_client.reject_cve("CVE-2022-20001")
    end
  end

  test "reject_cve can accept replaced_by" do
    cve_id = "CVE-2022-20001"
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has been published
    VCR.use_cassette("cve_api_reject_published_cve_replaced_by") do
      cve_api_client.reject_cve(cve_id, rejected_reasons: ["the reason"], replaced_by: ["CVE-2022-20002"])
    end

    WebMock.assert_requested(
      :put,
      "#{base_url}/api/cve/#{cve_id}/reject",
      headers: {
        "Content-Type" => "application/json",
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      body: JSON.generate({
        cnaContainer: {
          rejectedReasons: [
            {
              lang: "en",
              value: "the reason",
            },
          ],
          replacedBy: [
            "CVE-2022-20002",
          ],
        },
      }),
      times: 1,
    )
  end

  test "reject_cve raises an exception on an unsuccessful response" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_reject_published_cve_unsuccessful") do
      error = assert_raises(CVEAPI::Client::CVEAPIClientError) do
        cve_api_client.reject_cve("CVE-1234-5689", rejected_reasons: ["the reason"])
      end
      assert JSON.parse(error.message)["error"]
    end
  end

  test "reject_cve handles rejection when the CVE was never published" do
    cve_id = "CVE-2022-20001"
    cna_json_string = JSON.generate({
      cnaContainer: {
        rejectedReasons: [
          {
            lang: "en",
            value: "the reason",
          },
        ],
      },
    })
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has never been published
    VCR.use_cassette("cve_api_reject_unpublished_cve") do
      cve_api_client.reject_cve(cve_id, rejected_reasons: ["the reason"], previously_published: false)
    end

    WebMock.assert_requested(
      :post,
      "#{base_url}/api/cve/#{cve_id}/reject",
      headers: {
        "Content-Type" => "application/json",
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      body: cna_json_string,
      times: 1,
    )
  end

  test "reserve_cve" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_reserve_cve") do
      reserved_cves = cve_api_client.reserve_cve(amount: 3, cve_year: 2022)
      assert_equal 3, reserved_cves.size
      assert reserved_cves.first["cve_id"]
      assert_equal "2022", reserved_cves.first["cve_year"]
    end
  end

  test "reserve_cve raises an exception on an unsuccessful response" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_reserve_cve_unsuccessful") do
      error = assert_raises(CVEAPI::Client::CVEAPIClientError) do
        cve_api_client.reserve_cve(amount: 3, cve_year: 0)
      end
      assert JSON.parse(error.message)["error"]
    end
  end

  test "update_cve" do
    cve_id = "CVE-2022-20001"
    cve_json_string = load_cve_fixture(cve_id)
    cna_json_string = JSON.generate({
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    })
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has been created
    VCR.use_cassette("cve_api_update_cve") do
      cve_api_client.update_cve(cve_id, cna_json_string)
    end

    WebMock.assert_requested(
      :put,
      "#{base_url}/api/cve/#{cve_id}/cna",
      headers: {
        "Content-Type" => "application/json",
        "CVE-API-USER" => AdvisoryDB.cve_api_user,
        "CVE-API-ORG" => AdvisoryDB.cve_api_org,
        "CVE-API-KEY" => AdvisoryDB.cve_api_key,
      },
      body: cna_json_string,
      times: 1,
    )
  end

  test "update_cve returns the CVE JSON hash on a successful response" do
    cve_id = "CVE-2022-20001"
    cve_json_string = load_cve_fixture(cve_id)
    cna_json_string = JSON.generate({
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    })
    cve_api_client = CVEAPI::Client.new

    # assuming the CVE has been created
    VCR.use_cassette("cve_api_update_cve") do
      cve_hash = cve_api_client.update_cve(cve_id, cna_json_string)
      assert cve_hash["containers"]
    end
  end

  test "update_cve raises an exception on an unsuccessful response" do
    cve_api_client = CVEAPI::Client.new

    VCR.use_cassette("cve_api_update_cve_unsuccessful") do
      error = assert_raises(CVEAPI::Client::CVEAPIClientError) do
        cve_api_client.update_cve("CVE-2022-1234", {})
      end
      assert JSON.parse(error.message)["error"]
    end
  end
end
