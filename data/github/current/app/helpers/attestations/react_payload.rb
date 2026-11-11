# typed: true
# frozen_string_literal: true

module Attestations::ReactPayload

  # Builds payload from attestation data.
  # Supports two Proto types with different field structures:
  #   - AttestationSummary: has `subjects_count` and `subjects` array
  #   - AttestationItem: uses `subject_summary` enrichment (SubjectSummary with count + first_subject)
  # When `subjects:` is provided (e.g. from a ListSubjects call), it overrides both the subjects
  # array and the count (using subjects.length) from extract_subject_info.
  sig do
    params(
      attestation_summary: T.untyped,
      certificate_summary: T.untyped,
      subjects: T.nilable(T::Array[T::Hash[Symbol, String]])
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.attestation_summary_payload(attestation_summary, certificate_summary, subjects: nil)
    resolved_build_config_uri = format_resolved_build_config_uri(certificate_summary.run_invocation_uri)
    resolved_source_repository_commit_uri = format_resolved_source_repository_commit_uri(
      certificate_summary.source_repository_uri,
      certificate_summary.source_repository_digest)
    build_config_display_name = format_build_config_display_name(
      certificate_summary.build_config_uri,
      certificate_summary.source_repository_uri)

    # Resolve subjects count and subjects from available data.
    # When subjects are provided externally (e.g. from ListSubjects), use those.
    # Otherwise fall back to extract_subject_info for inline subject data.
    extracted_count, extracted_subjects = extract_subject_info(attestation_summary)
    resolved_subjects = subjects || extracted_subjects
    resolved_count = subjects ? subjects.length : extracted_count

    # NOTE: Twirp interfaces need to be converted to a hash for React SSR to work, anything that can't be serialized
    # into a hash is undefined in SSR mode so breaks client hydration and causes hard to debug issues
    {
      id:            attestation_summary.id,
      predicateType: attestation_summary.predicate_type,
      createdAt:     attestation_summary.created_at.to_time, # Convert Google::Protobuf::Timestamp to string
      subjectsCount: resolved_count,
      subjects:      resolved_subjects,
    }.merge!({
      buildConfigDisplayName:              build_config_display_name,
      resolvedBuildConfigUri:              resolved_build_config_uri,
      resolvedSourceRepositoryCommitUri:   resolved_source_repository_commit_uri,

      buildConfigDigest:                   certificate_summary.build_config_digest,
      buildConfigUri:                      certificate_summary.build_config_uri,
      buildSignerDigest:                   certificate_summary.build_signer_digest,
      buildSignerUri:                      certificate_summary.build_signer_uri,
      buildTrigger:                        certificate_summary.build_trigger,
      issuer:                              certificate_summary.issuer,
      runInvocationUri:                    certificate_summary.run_invocation_uri,
      runnerEnvironment:                   certificate_summary.runner_environment,
      sourceRepositoryDigest:              certificate_summary.source_repository_digest,
      sourceRepositoryIdentifier:          certificate_summary.source_repository_identifier,
      sourceRepositoryOwnerIdentifier:     certificate_summary.source_repository_owner_identifier,
      sourceRepositoryOwnerUri:            certificate_summary.source_repository_owner_uri,
      sourceRepositoryRef:                 certificate_summary.source_repository_ref,
      sourceRepositoryUri:                 certificate_summary.source_repository_uri,
      sourceRepositoryVisibilityAtSigning: certificate_summary.source_repository_visibility_at_signing,
    })
  end

  sig { params(bundle: T.untyped).returns(T::Array[String]) }
  def self.get_attestation_lines(bundle)
    payload_json = bundle.dsse_envelope.payload
    pretty_payload = JSON.pretty_generate(JSON.parse(payload_json))
    escaped_payload = ERB::Util.html_escape_once(pretty_payload)
    escaped_payload.split("\n")
  end

  sig { params(build_config_uri: String, source_repository_uri: String).returns(String) }
  def self.format_build_config_display_name(build_config_uri, source_repository_uri)
    # Ignore the @refs/* suffix on BuildConfigURI as we only want to display the relative config file path
    split_build_config_uri = build_config_uri.split("@")
    # Relative pathname to the workflow file
    build_config_display_name = T.must(split_build_config_uri[0]).gsub("#{source_repository_uri}/", "")
  end

  sig { params(run_invocation_uri: String).returns(String) }
  def self.format_resolved_build_config_uri(run_invocation_uri)
    split_run_invocation_uri = run_invocation_uri.split("/attempts/")
    parts = [
      split_run_invocation_uri[0],
      "workflow",
    ]

    resolved_build_config_uri = parts.join("/")
  end

  sig { params(source_repository_uri: String, source_repository_digest: String).returns(String) }
  def self.format_resolved_source_repository_commit_uri(source_repository_uri, source_repository_digest)
    "#{source_repository_uri}/tree/#{source_repository_digest}"
  end

  # Convert array of Proto::TrustMetadataApi::V0::Subject to a hash of subjects
  # subjects_proto should be [Proto::TrustMetadataApi::V0::Subject] but it's breaking Sorbet right now
  sig { params(subjects_proto: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
  def self.format_subjects(subjects_proto)
    subjects = subjects_proto.map do |subject|
      {
        subjectName:   subject.subject_name,
        subjectDigest: subject.subject_digest,
      }
    end
  end

  # Extracts subject count and subjects array from an attestation Proto.
  #
  # AttestationItem (new endpoint): reads from the subject_summary enrichment
  #   which provides count and an optional first_subject.
  # AttestationSummary (old endpoint): reads subjects_count and subjects array directly.
  sig { params(attestation: T.untyped).returns([Integer, T::Array[T::Hash[Symbol, String]]]) }
  def self.extract_subject_info(attestation)
    if attestation.respond_to?(:has_subject_summary?) && attestation.has_subject_summary?
      # AttestationItem: reads count and first subject from the subject_summary enrichment.
      summary = attestation.subject_summary
      count = summary.count.to_i
      subjects = if summary.has_first_subject?
        [{ subjectName: summary.first_subject.subject_name, subjectDigest: summary.first_subject.subject_digest }]
      else
        []
      end
      [count, subjects]
    elsif attestation.respond_to?(:subjects_count)
      # AttestationSummary: reads subjects_count and the full subjects array.
      count = attestation.subjects_count.to_i
      subjects = if attestation.respond_to?(:subjects) && attestation.subjects.present?
        format_subjects(attestation.subjects)
      else
        []
      end
      [count, subjects]
    else
      [0, []]
    end
  end
end
