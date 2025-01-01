# typed: true
# frozen_string_literal: true
require "test_helper"

class TrustMetadata::SigstoreBundleTest < GitHub::TestCase
  fixtures do
    @bundle_fixture = JSON.parse(Rails.root.join("test/fixtures/attestations/sigstorejs100_provenance_bundle.json").read)
  end

  test "it properly sets a predicate type & has a minimal validity check" do
    bundle = TrustMetadata::SigstoreBundle.new(@bundle_fixture)

    assert_equal "https://slsa.dev/provenance/v0.2", bundle.predicate_type
    assert bundle.valid?
  end

  test "it has a minimal equality comparison" do
    bundle1 = TrustMetadata::SigstoreBundle.new(@bundle_fixture)
    bundle2 = TrustMetadata::SigstoreBundle.new(@bundle_fixture)

    publish_bundle_fixture = JSON.parse(Rails.root.join("test/fixtures/attestations/sigstorejs100_publish_bundle.json").read)

    bundle3 = TrustMetadata::SigstoreBundle.new(publish_bundle_fixture)

    assert_equal bundle1, bundle2
    assert_equal bundle2, bundle1
    assert_equal bundle1, bundle1

    refute_equal bundle1, bundle3
  end

  test "it doesn't throw an exception up if fed invalid hash" do
    bad_bundle1 = {
      "mediaType" => "vnd.dev.sigstore.bundle",
      "dsseEnvelope" => {
        "payload" => {
          "predicateType" => nil
        }
      }
    }

    bundle1 = TrustMetadata::SigstoreBundle.new(bad_bundle1)
    refute bundle1.valid?

    bad_bundle2 = {
      "mediaType" => "vnd.dev.sigstore.bundle",
      "dsseEnvelope" => {
        "payload" => {
          "predicateType" => Base64.encode64("{invalidjson}")
        }
      }
    }

    bundle2 = TrustMetadata::SigstoreBundle.new(bad_bundle2)
    refute bundle2.valid?

    bad_bundle3 = {
      "mediaType" => "vnd.dev.sigstore.bundle",
      "dsseEnvelope" => {
        "payload" => nil
      }
    }

    bundle3 = TrustMetadata::SigstoreBundle.new(bad_bundle3)
    refute bundle3.valid?

    bad_bundle4 = {}

    bundle4 = TrustMetadata::SigstoreBundle.new(bad_bundle4)
    refute bundle4.valid?
  end
end
