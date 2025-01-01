# typed: true
require 'minitest/autorun'
require "minitest/snapshots"

require_relative "../lib/monolith-twirp-attester"

class ReleasePredicateTest < Minitest::Test

  def test_release_predicate_message_full
    pred = MonolithTwirp::Attester::V0::ReleasePredicate.new(
      purl: "pkg:github-release/foo/bar@v1.0.0?repository_url=https://contoso.ghe.com",
      release_id: "10",
      tag: "v1.0.0",
      repository: "foo/bar",
      repository_id: "1974",
      owner_id: "2004",
      enterprise: "contoso.ghe.com",
      enterprise_id: "2007"
    )
    refute_nil pred

    # Serialize to JSON
    json = MonolithTwirp::Attester::V0::ReleasePredicate.encode_json(pred)
    assert_matches_snapshot json
  end

  def test_release_predicate_message_minimal
    pred = MonolithTwirp::Attester::V0::ReleasePredicate.new(
      purl: "pkg:github-release/foo/bar@v1.0.0?repository_url=https://contoso.ghe.com",
      release_id: "10",
      tag: "v1.0.0",
      repository: "foo/bar",
      repository_id: "1974",
      owner_id: "2004"
    )
    refute_nil pred

    # Serialize to JSON
    json = MonolithTwirp::Attester::V0::ReleasePredicate.encode_json(pred)
    assert_matches_snapshot json
  end

  def test_full_release_statement
    pred = MonolithTwirp::Attester::V0::ReleasePredicate.new(
      purl: "pkg:github-release/foo/bar@v1.0.0?repository_url=https://contoso.ghe.com",
      release_id: "10",
      tag: "v1.0.0",
      repository: "foo/bar",
      repository_id: "1974",
      owner_id: "2004",
      enterprise: "contoso.ghe.com",
      enterprise_id: "2007"
    )

    sub = InTotoAttestation::V1::ResourceDescriptor.new(
      name: "foo_darwin_amd64.tar.gz",
      digest: { sha256: "a1b2c3" },
    )

    # Since the in-toto statement defines "predicate" as a
    # google.protobuf.Struct we need to convert the ReleasePredicate to a
    # google.protobuf.Struct by round-tripping through JSON.
    pred_json = MonolithTwirp::Attester::V0::ReleasePredicate.encode_json(pred)
    pred_struct = Google::Protobuf::Struct.decode_json(pred_json)

    stmt = InTotoAttestation::V1::Statement.new(
      type: "https://in-toto.io/Statement/v1",
      subject: [sub],
      predicate_type: "https://in-toto.io/attestation/release/v0.1",
      predicate: pred_struct,
    )

    # Serialize to JSON
    json = InTotoAttestation::V1::Statement.encode_json(stmt)
    assert_matches_snapshot json
  end
end
