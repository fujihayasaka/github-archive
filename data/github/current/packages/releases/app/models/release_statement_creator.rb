# typed: true
# frozen_string_literal: true

require "sigstore-proto"
require "monolith-twirp-attester"

module ReleaseStatementCreator
  STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
  PREDICATE_TYPE_V02 = "https://in-toto.io/attestation/release/v0.2"
  MAX_ASSET_SUBJECTS = 1023

  sig { params(release: Release).returns(InTotoAttestation::V1::Statement) }
  def self.assemble_statement(release)
    if release.release_assets.length > MAX_ASSET_SUBJECTS
      raise "release attestations limited to #{MAX_ASSET_SUBJECTS} assets"
    end

    repo = T.must(release.repository)
    # Per the PURL spec the "version" must be percent-encoded
    encoded_tag = CGI.escape(release.tag_name)
    purl = "pkg:github/#{repo.name_with_display_owner}@#{encoded_tag}"

    pred = MonolithTwirp::Attester::V0::ReleasePredicate.new(
      database_id: release.id.to_s,
      owner_id: repo.owner_id.to_s,
      package_id: release.repository_id.to_s,
      repository_id: release.repository_id.to_s,
      repository: repo.name_with_display_owner,
      tag: release.tag_name,
    )

    # Collect tenant information if available
    if current_tenant = GitHub::CurrentTenant.get.presence
      purl += "?repository_url=https:%2F%2F#{current_tenant.slug}"
      pred.enterprise = current_tenant.slug
      pred.enterprise_id = current_tenant.id.to_s
    end

    pred.purl = purl

    # Translate release assets into subjects
    subs = release.release_assets.map do |asset|
      asset_digest = asset.digest
      if asset_digest.nil?
        raise Releases::Error, "Release asset '#{asset.name}' is missing a digest, cannot assemble statement"
      end

      algo, digest = asset_digest.split(":", 2)
      InTotoAttestation::V1::ResourceDescriptor.new(
        name: asset.name,
        digest: { algo => digest },
      )
    end

    # Add subject for the release's tag/commit. Derive the digest algorithm
    # from the repository's hash algorithm so SHA-256 repositories produce
    # the correct algorithm label.
    tag_sub = InTotoAttestation::V1::ResourceDescriptor.new(
      uri: purl,
      digest: { repo.hash_algo.name => release.tag.sha },
    )
    subs.unshift(tag_sub)

    # Since the in-toto statement defines "predicate" as a google.protobuf.Struct we need round-trip the
    # ReleasePredicate through JSON to get the correct format.
    pred_struct = Google::Protobuf::Struct.decode_json(
      MonolithTwirp::Attester::V0::ReleasePredicate.encode_json(pred))

    InTotoAttestation::V1::Statement.new(
      type: STATEMENT_TYPE,
      subject: subs,
      predicate_type: PREDICATE_TYPE_V02,
      predicate: pred_struct,
    )
  end
end
