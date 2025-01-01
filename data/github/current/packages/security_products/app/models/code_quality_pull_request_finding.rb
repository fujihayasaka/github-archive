# typed: strict
# frozen_string_literal: true

# TODO: we only store the protobuf finding and some static metadata for each finding.
# Findings also have local state in dotcom, such as if they have been fixed
# in the current analysis of if they have been dismissed. We need to record
# this information in the kv store as well.

# TODO: we have a limit of 64KB per value in the KV store.
# Some findings could exceed this, e.g. if they have complex dataflow paths or
# complex autofix suggestions.

# TODO: when we make this a proper db table we should delete the dependency of
# PullRequestReviewsController#more_threads on the Notify cluster
class CodeQualityPullRequestFinding

  module AlertDetails
    extend T::Helpers
    interface!

    sig { abstract.returns(T.any(Integer, String)) }
    def id; end

    sig { abstract.returns(String) }
    def alert_title; end

    sig { abstract.returns(String) }
    def alert_message; end

    sig { abstract.returns(String) }
    def tool_name; end

    sig { abstract.returns(T.nilable(Integer)) }
    def alert_number; end

    sig { abstract.returns(String) }
    def warning_level; end
  end

  SuggestedFix = T.type_alias do
    T.any(
      Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::SuggestedFix,
      Turboscan::Proto::SuggestedFixAlert
    )
  end

  class SuggestedFixAlert

    sig { params(finding: CodeQualityPullRequestFinding).void }
    def initialize(finding:)
      @finding = finding
    end

    sig { returns(T.nilable(Google::Protobuf::Timestamp)) }
    def created_at
      nil
    end

    sig { returns(T.nilable(String)) }
    def rule_sarif_identifier
      nil
    end

    sig { returns(Symbol) }
    def state
      if @finding.suggested_fix_applied?
        :SUGGESTED_FIX_ALERT_STATE_APPLIED
      elsif suggested_fix.nil?
        :SUGGESTED_FIX_ALERT_STATE_ERROR
      else
        :SUGGESTED_FIX_ALERT_STATE_VALID
      end
      # TODO: handle outdated suggestions
    end

    sig { returns(T.nilable(Integer)) }
    def state_updated_actor_id
      nil
    end

    sig { returns(T.nilable(Google::Protobuf::Timestamp)) }
    def state_updated_at
      nil
    end

    sig { returns(T.nilable(SuggestedFix)) }
    def suggested_fix
      @finding.proto_finding.suggested_fix
    end

    sig { returns(T.nilable(String)) }
    def validations_summary
      nil
    end
  end

  include AlertDetails

  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_KEY = "code_quality.pull_request_findings"
  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_VERSION = "1"
  CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_EXPIRY_DAYS = 90

  sig { returns(Integer) }
  attr_reader :repository_id

  sig { returns(Integer) }
  attr_reader :pull_request_id

  sig { returns(T.nilable(String)) }
  attr_reader :analysis_configuration

  sig { returns(T.nilable(String)) }
  attr_reader :commit_oid

  sig { returns(Integer) }
  attr_reader :review_comment_id

  sig { returns(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding) }
  attr_reader :proto_finding

  sig { returns(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule) }
  attr_reader :proto_rule

  # Whether the suggested fix has been applied to the code.
  sig { returns(T::Boolean) }
  attr_accessor :suggested_fix_applied

  sig { returns(Symbol) }
  attr_reader :resolution

  sig { returns(T.nilable(DateTime)) }
  attr_reader :resolved_at

  sig { returns(T.nilable(Integer)) }
  attr_reader :resolver_id

  sig { returns(T.nilable(String)) }
  attr_reader :resolution_note

  sig { returns(T.nilable(String)) }
  attr_reader :resolver_login

  sig { returns(T::Boolean) }
  attr_reader :fixed

  sig { returns(T.nilable(DateTime)) }
  attr_reader :fixed_at

  delegate :annotation_result, :metadata, to: :proto_finding

  sig do
    params(repository_id: Integer,
      pull_request_id: Integer,
      analysis_configuration: T.nilable(String),
      commit_oid: T.nilable(String),
      review_comment_id: Integer,
      proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
      proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
      suggested_fix_applied: T::Boolean,
      resolution: Symbol,
      resolved_at: T.nilable(DateTime),
      resolver_id: T.nilable(Integer),
      resolution_note: T.nilable(String),
      resolver_login: T.nilable(String),
      fixed: T::Boolean,
      fixed_at: T.nilable(DateTime),
    ).void
  end
  def initialize(repository_id:, pull_request_id:, analysis_configuration:, commit_oid:, review_comment_id:, proto_finding:, proto_rule:, suggested_fix_applied: false, resolution: :NO_RESOLUTION, resolved_at: nil, resolver_id: nil, resolution_note: nil, resolver_login: nil, fixed: false, fixed_at: nil)
    @repository_id = repository_id
    @pull_request_id = pull_request_id
    @analysis_configuration = analysis_configuration
    @commit_oid = commit_oid
    @review_comment_id = review_comment_id
    @proto_finding = proto_finding
    @proto_rule = proto_rule
    @suggested_fix_applied = suggested_fix_applied
    @resolution = resolution
    @resolved_at = resolved_at
    @resolver_id = resolver_id
    @resolution_note = resolution_note
    @resolver_login = resolver_login
    @fixed = fixed
    @fixed_at = fixed_at
  end

  # Save the finding to the KV store. The stored value will expire after 90 days.
  sig { void }
  def save
    CodeScanning::KV.store.set(key, serialize, expires: CODE_QUALITY_PULL_REQUEST_FINDINGS_KV_EXPIRY_DAYS.days.from_now)
    GlobalInstrumenter.instrument("code_quality.pull_request_finding", {
      repository_id: @repository_id,
      pull_request_id: @pull_request_id,
      review_comment_id: @review_comment_id,
      stable_id: stable_id,
      rule_sarif_identifier: rule_sarif_identifier,
      severity: severity_name,
      resolution: @resolution,
      fixed: @fixed,
      fixed_at: @fixed_at,
      analysis_configuration: @analysis_configuration,
    })
  end

  # Update the finding and the rule to reflect the output of a more recent analysis.
  sig do params(
    analysis_configuration: String,
    finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
    rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule
  ).void
  end
  def update!(analysis_configuration:, finding:, rule:)
    @proto_finding = finding
    @proto_rule = rule
    save
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

  # Mark the resoultion status
  sig do
    params(
      resolution: Symbol,
      resolver_id: T.nilable(Integer),
      resolution_note: T.nilable(String),
      resolver_login: T.nilable(String),
      resolved_at: T.nilable(DateTime),
    ).void
  end
  def set_resolution_status(resolution:, resolver_id:, resolution_note:, resolver_login:, resolved_at: DateTime.now)
    raise ArgumentError, "`resolution` is not valid" unless Turboscan::Proto::ResultResolution.const_defined?(resolution)

    if !resolution_note.nil?
      raise ArgumentError, "`resolution note` exceeds character count " unless resolution_note.size <= 1024
    end

    @resolved_at = resolved_at
    @resolution = resolution
    @resolver_id = resolver_id
    @resolution_note = resolution_note
    @resolver_login = resolver_login
    save
  end

  # Mark the finding as having the suggested fix not applied.
  sig { void }
  def mark_suggested_fix_as_not_applied
    @suggested_fix_applied = false
    save
  end

  sig { returns(T::Boolean) }
  def suggested_fix_applied?
    @suggested_fix_applied
  end

  sig { void }
  def fix!
    @fixed = true
    @fixed_at = DateTime.now
    save
  end

  sig { returns(T::Boolean) }
  def fixed?
    @fixed
  end

  sig { returns(T::Boolean) }
  def resolved?
    @resolution != :NO_RESOLUTION
  end

  sig { returns(T.nilable(String)) }
  def stable_id
    annotation_result&.result&.stable_id || nil
  end

  sig { returns(T.nilable(String)) }
  def rule_sarif_identifier
    proto_rule.sarif_identifier
  end

  # Methods that DFAs rely on

  sig { override.returns(String) }
  def id
    "#{repository_id}:#{pull_request_id}:#{review_comment_id}"
  end

  sig { override.returns(String) }
  def alert_title
    proto_rule.short_description
  end

  sig { override.returns(String) }
  def alert_message
    annotation_result&.result&.message_text || "No message text"
  end

  sig { returns(T::Array[Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RelatedLocation]) }
  def related_locations
    annotation_result&.related_locations.to_a
  end

  sig { returns(T.nilable(String)) }
  def message_markdown
    annotation_result&.result&.message_markdown
  end

  # TODO: this is an artifact of matching the CodeScanningReviewComment model.
  # No code quality functionality should rely on this, as it is mostly a turboscan detail.
  # We explicitly return a nil here to ensure that we cannot rely on this.
  sig { override.returns(T.nilable(Integer)) }
  def alert_number
    nil
  end

  # TODO: this may eventually need to be sourced from protobuf data
  sig { override.returns(String) }
  def tool_name
    "CodeQL"
  end

  sig { returns(Integer) }
  def severity_value
    proto_severity = proto_rule.severity
    if proto_severity.is_a?(Integer)
      proto_severity
    else
      if Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity.const_defined?(proto_severity)
        Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity.const_get(proto_severity)
      else
        Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_UNKNOWN
      end
    end
  end

  sig { returns(String) }
  def severity_name
    case severity_value
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_ERROR
      "error"
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_WARNING
      "warning"
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_NOTE
      "note"
    else
      "unknown"
    end
  end

  sig { override.returns(String) }
  def warning_level
    case severity_value
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_ERROR
      "failure"
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_WARNING
      "warning"
    when Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_NOTE
      "note"
    else
      "unknown"
    end
  end

  sig { returns(T.nilable(SuggestedFixAlert)) }
  def suggested_fix_alert
    SuggestedFixAlert.new(finding: self)
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
      "analysis_configuration" => analysis_configuration,
      "commit_oid" => commit_oid,
      "review_comment_id" => review_comment_id.to_s,
      "proto_finding_serialized" => proto_finding_serialized,
      "proto_rule_serialized" => proto_rule_serialized,
      "suggested_fix_applied" => suggested_fix_applied.to_s,
      "resolution" => resolution.to_s,
      "resolved_at" => resolved_at.to_s,
      "resolver_id" => resolver_id.to_s,
      "resolution_note" => resolution_note.to_s,
      "resolver_login" => resolver_login.to_s,
      "fixed" => fixed.to_s,
      "fixed_at" => fixed_at.to_s,
    }
  end

  class << self

    # Construct a new `CodeQualityPullRequestFinding` from a review comment
    # and a protobuf finding.
    sig do
      params(
        review_comment: PullRequestReviewComment,
        analysis_configuration: T.nilable(String),
        commit_oid: String,
        proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule
      ).returns(CodeQualityPullRequestFinding)
    end
    def finding(review_comment:, analysis_configuration:, commit_oid:, proto_finding:, proto_rule:)
      CodeQualityPullRequestFinding.new(
        repository_id: review_comment.repository_id,
        pull_request_id: review_comment.pull_request_id,
        analysis_configuration:,
        commit_oid:,
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
      analysis_configuration = obj["analysis_configuration"]
      commit_oid = obj["commit_oid"]
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
      resolution =  obj["resolution"]&.to_sym || :NO_RESOLUTION
      resolved_at = obj["resolved_at"]
      resolved_at = resolved_at.present? ? resolved_at.to_datetime : nil
      resolver_id = obj["resolver_id"].present? ? Integer(obj["resolver_id"]) : nil
      resolution_note = obj["resolution_note"].present? ? obj["resolution_note"] : nil
      resolver_login = obj["resolver_login"].present? ? obj["resolver_login"] : nil
      fixed = obj["fixed"].present? ? obj["fixed"] == "true" : false
      fixed_at = obj["fixed_at"]
      fixed_at = fixed_at.present? ? fixed_at.to_datetime : nil

      new(repository_id:,
      pull_request_id:,
      analysis_configuration:,
      commit_oid:,
      review_comment_id:,
      proto_finding:,
      proto_rule:,
      suggested_fix_applied:,
      resolution:,
      resolved_at:,
      resolver_id:,
      resolution_note:,
      resolver_login:,
      fixed:,
      fixed_at:,
      )
    end
  end
end
