# typed: strict
# frozen_string_literal: true

# TODO: we only store the protobuf finding and some static metadata for each finding.
# Findings also have local state in dotcom, such as if they have been fixed
# in the current analysis of if they have been dismissed. We need to record
# this information in the kv store as well.

# TODO: we have a limit of 64KB per value in the KV store.
# Some findings could exceed this, e.g. if they have complex dataflow paths or
# complex autofix suggestions.

class CodeQualityPullRequestFinding
  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_KEY = "code_quality.pull_request_findings"
  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_VERSION = "1"
  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_EXPIRY_DAYS = 90

  sig { returns(Integer) }
  attr_reader :repository_id

  sig { returns(Integer) }
  attr_reader :pull_request_id

  sig { returns(Integer) }
  attr_reader :review_comment_id

  sig { returns(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding) }
  attr_reader :proto_finding

  sig { returns(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule) }
  attr_reader :proto_rule

  # Whether the suggested fix has been applied to the code.
  sig { returns(T::Boolean) }
  attr_accessor :suggested_fix_applied

  delegate :annotation_result, :metadata, :suggested_fix, to: :proto_finding

  sig do
    params(repository_id: Integer,
      pull_request_id: Integer,
      review_comment_id: Integer,
      proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
      proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
      suggested_fix_applied: T::Boolean,
    ).void
  end
  def initialize(repository_id:, pull_request_id:, review_comment_id:, proto_finding:, proto_rule:, suggested_fix_applied: false)
    @repository_id = repository_id
    @pull_request_id = pull_request_id
    @review_comment_id = review_comment_id
    @proto_finding = proto_finding
    @proto_rule = proto_rule
    @suggested_fix_applied = suggested_fix_applied
  end

  # Save the finding to the KV store. The stored value will expire after 90 days.
  sig { void }
  def save
    CodeScanning::KV.store.set(key, serialize, expires: CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_EXPIRY_DAYS.days.from_now)
  end

  # Serialize the finding to a base64-encoded, compressed string for storage in the KV store.
  # This is the inverse of `CodeQualityPullRequestFinding.deserialize_finding`
  sig { returns(String) }
  def serialize
    serialized_finding_string = to_obj.to_json
    compressed = Zlib::Deflate.deflate(serialized_finding_string)
    Base64.strict_encode64(compressed)
  end

  # Mark the finding as having the suggested fix applied.
  sig { void }
  def mark_suggested_fix_as_applied
    @suggested_fix_applied = true
    save
  end

  sig { returns(T::Boolean) }
  def suggested_fix_applied?
    @suggested_fix_applied
  end

  private

  # Get the KV key used to store this finding.
  sig { returns(String) }
  def key
    CodeQualityPullRequestFinding.kv_store_key(repository_id:, pull_request_id:, review_comment_id:)
  end

  # Convert the finding to a hash object.
  # This object can then be serialized for storage in the KV store.
  # This is the inverse of `CodeQualityPullRequestFinding.from_obj`
  sig { returns(T::Hash[String, String]) }
  def to_obj
    proto_finding_serialized = Google::Protobuf.encode_json(proto_finding)
    proto_rule_serialized = Google::Protobuf.encode_json(proto_rule)
    {
      "repository_id" => repository_id.to_s,
      "pull_request_id" => pull_request_id.to_s,
      "review_comment_id" => review_comment_id.to_s,
      "proto_finding_serialized" => proto_finding_serialized,
      "proto_rule_serialized" => proto_rule_serialized,
      "suggested_fix_applied" => suggested_fix_applied.to_s
    }
  end

  class << self

    # Construct a new `CodeQualityPullRequestFinding` from a review comment
    # and a protobuf finding.
    sig do
      params(
        review_comment: PullRequestReviewComment,
        proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule
      ).returns(CodeQualityPullRequestFinding)
    end
    def finding(review_comment:, proto_finding:, proto_rule:)
      CodeQualityPullRequestFinding.new(
        repository_id: review_comment.repository_id,
        pull_request_id: review_comment.pull_request_id,
        review_comment_id: review_comment.id,
        proto_finding:,
        proto_rule:
      )
    end

    # Find all code quality findings for a given PR.
    sig do
      params(repository: Repository, pull_request: PullRequest)
      .returns(T::Array[CodeQualityPullRequestFinding])
    end
    def find_all(repository:, pull_request:)
      key_prefix = kv_store_key_prefix(repository_id: repository.id, pull_request_id: pull_request.id)

      # Get all findings for this repo:PR from the KV store
      result = CodeScanning::KV.store.mget_prefix(key_prefix)
      return [] unless result && result.ok?

      data_hash = result.value!
      return [] unless data_hash.present?

      serialized_findings_strings = data_hash.values

      # Deserialize each finding string and return an array of CodeQualityPullRequestFinding objects
      deserialized_findings = serialized_findings_strings.map do |findings_data_string|
        deserialize_finding(findings_data_string)
      end

      # Sort findings by review_comment_id to ensure consistent order
      deserialized_findings.sort_by(&:review_comment_id)
    end

    # Find the code quality finding for a specific review comment.
    sig do
      params(review_comment: PullRequestReviewComment
      ).returns(T.nilable(CodeQualityPullRequestFinding))
    end
    def find(review_comment:)
      repository_id = review_comment.repository_id
      pull_request_id = review_comment.pull_request_id
      return nil unless repository_id && pull_request_id

      key = kv_store_key(repository_id:, pull_request_id:, review_comment_id: review_comment.id)

      # Get the finding for this repo:PR:review_comment from the KV store
      result = CodeScanning::KV.store.get(key)
      serialized_finding_string = result&.ok? ? result.value! : nil
      return nil unless serialized_finding_string.present?

      # Deserialize the finding string and return a CodeQualityPullRequestFinding object
      deserialize_finding(serialized_finding_string)
    end

    sig do
      params(
        repository_id: Integer, pull_request_id: Integer, review_comment_id: Integer
      ).returns(String)
    end
    def kv_store_key(repository_id:, pull_request_id:, review_comment_id:)
      "#{kv_store_key_prefix(repository_id:, pull_request_id:)}#{review_comment_id}"
    end

    private

    sig do
      params(
        repository_id: Integer, pull_request_id: Integer
      ).returns(String)
    end
    def kv_store_key_prefix(repository_id:, pull_request_id:)
      "#{CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_KEY}.#{CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_VERSION}:#{repository_id}:#{pull_request_id}:"
    end

    # Given a base64-encoded, compressed string representing a serialized finding,
    # deserialize it into a CodeQualityPullRequestFinding object.
    # This is the inverse of `CodeQualityPullRequestFinding#serialize`
    sig { params(serialized_finding_string_base64: String).returns(CodeQualityPullRequestFinding) }
    def deserialize_finding(serialized_finding_string_base64)
      compressed = Base64.decode64(serialized_finding_string_base64)
      serialized_finding_string = Zlib::Inflate.inflate(compressed)
      finding_obj = JSON.parse(serialized_finding_string)
      from_obj(finding_obj)
    end

    # Create a CodeQualityPullRequestFinding from a hash object
    # This is the inverse of `CodeQualityPullRequestFinding#to_obj`
    sig { params(obj: T::Hash[String, String]).returns(CodeQualityPullRequestFinding) }
    def from_obj(obj)
      repository_id = Integer(obj["repository_id"])
      pull_request_id = Integer(obj["pull_request_id"])
      review_comment_id = Integer(obj["review_comment_id"])
      proto_finding = Google::Protobuf.decode_json(
        Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        obj["proto_finding_serialized"]
      )
      proto_rule = Google::Protobuf.decode_json(
        Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
        obj["proto_rule_serialized"]
      )
      suggested_fix_applied = obj["suggested_fix_applied"].present? ? obj["suggested_fix_applied"] == "true" : false
      new(repository_id:, pull_request_id:, review_comment_id:, proto_finding:, proto_rule:, suggested_fix_applied:)
    end
  end
end
