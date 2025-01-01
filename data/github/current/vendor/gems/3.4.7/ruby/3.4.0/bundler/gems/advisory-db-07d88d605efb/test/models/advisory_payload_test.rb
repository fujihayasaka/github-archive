# frozen_string_literal: true

require "test_helper"

class AdvisoryPayloadTest < ActiveSupport::TestCase
  setup do
    # Allow other feature flag checks beyond the expected calls below
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "valid? returns true on a valid advisory payload" do
    data = create :advisory_payload
    advisory_payload = AdvisoryPayload.new(data: data)

    assert advisory_payload.valid?
  end

  test "valid? returns true on an advisory payload with a nil CWE id" do
    data = create :advisory_payload, cwe_ids: nil
    advisory_payload = AdvisoryPayload.new(data: data)

    assert advisory_payload.valid?
  end

  test "valid? returns true on an advisory payload with a an empty CWE id array" do
    data = create :advisory_payload, cwe_ids: []
    advisory_payload = AdvisoryPayload.new(data: data)

    assert advisory_payload.valid?
  end

  test "valid? returns false on an advisory payload with a non existent CWE id" do
    data = create :advisory_payload, cwe_ids: ["CWE-999999999"]
    advisory_payload = AdvisoryPayload.new(data: data)

    refute advisory_payload.valid?
  end

  test "getters should adopt UTF-8 encoding if any uses ASCII-8BIT" do
    advisory_review = create(:advisory_review)
    ActiveRecord::Base.connection.execute("UPDATE advisory_reviews SET advisory_payload = '---\ncvss_v3: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N\ndescription: !binary |-\n  VGhlIGBjb3Ntb3Nfc2RrYCBjcmF0ZSwgd2hpY2ggcHJvdmlkZXMgYSBiYXNpYyBSdXN0IFNESyBmb3IgdGhlIENvc21vcyBlY29zeXN0ZW0sCmhhcyByZWJyYW5kZWQgdG8g4oCcQ29zbVJT4oCdIGluIHRoZSBzcGlyaXQgb2Ygb3RoZXIgcHJvamVjdHMgbGlrZSBDb3NtSlMgYW5kIENvc21XYXNtLgoKWW91IGNhbiBmaW5kIHRoZSBuZXcgaG9tZSBoZXJlOgoKaHR0cHM6Ly9naXRodWIuY29tL2Nvc21vcy9jb3Ntb3MtcnVzdC90cmVlL21haW4vY29zbXJzCgpUaGUgbmV3IGNyYXRlIG5hbWUgaXMgYGNvc21yc2A6CgpodHRwczovL2NyYXRlcy5pby9jcmF0ZXMvY29zbXJzCg==\nreferences:\n- https://github.com/cosmos/cosmos-rust/issues/113\n- https://rustsec.org/advisories/RUSTSEC-2021-0099.html\nseverity: \nsummary: Crate has been renamed to `cosmrs`\nvulnerabilities: {}\nwithdrawn: false\n' WHERE id = #{advisory_review.id};")

    advisory_payload = AdvisoryPayload.new(data: advisory_review.reload.advisory_payload)

    ["cvss_v3", "description", "summary"].each do |field_name|
      assert_equal Encoding::UTF_8, advisory_payload.send(field_name).encoding, "Wrong encoding for #{field_name}"
    end
  end

  test "out of order vulnerabilities are sorted and validated" do
    vulnerabilities_payload = Array.new(15) do |index|
      [index, create(:vulnerability_payload)]
    end
    vulnerabilities_payload.sort_by! { |tuple| tuple.first.to_s }

    data = create(:advisory_payload, vulnerabilities: vulnerabilities_payload.to_h)
    payload = AdvisoryPayload.new(data: data)

    assert payload.valid?
    assert_equal (0...15).to_a, payload.vulnerabilities.keys
  end
end
