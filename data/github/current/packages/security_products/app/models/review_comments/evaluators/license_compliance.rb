# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/dependencygraph/v1/entities/alert_status_pb"
require "hydro/schemas/github/dependencygraph/v1/entities/closure_reason_pb"

class ReviewComments::Evaluators::LicenseCompliance < ReviewComments::AutomatedReviewCommentEvaluator
  # Metadata keys for storing alert status information in AutomatedReviewComment.metadata
  METADATA_KEY_ALERT_STATUS = "license_compliance_alert_status"
  METADATA_KEY_ACTOR_ID = "license_compliance_actor_id"
  METADATA_KEY_CLOSURE_REASON = "license_compliance_closure_reason"

  # Proto enum modules - canonical definitions for alert status and closure reason values.
  # Metadata values are the string form of these proto enum names, set by
  # LicenseComplianceAlertStatusChangedProcessor#update_comment_metadata
  AlertStatusProto = Hydro::Schemas::Github::Dependencygraph::V1::Entities::AlertStatus
  ClosureReasonProto = Hydro::Schemas::Github::Dependencygraph::V1::Entities::ClosureReason

  # Validates that a symbol is a valid proto enum value and returns it as a string.
  sig { params(enum_mod: T.untyped, const_name: Symbol).returns(String) }
  private_class_method def self.proto_enum_name(enum_mod, const_name)
    raise ArgumentError, "Unknown proto enum value: #{const_name}" if enum_mod.resolve(const_name).nil?
    const_name.to_s
  end

  # Alert status string values derived from alert_status.proto
  ALERT_STATUS_OPEN = T.let(proto_enum_name(AlertStatusProto, :ALERT_STATUS_OPEN), String)
  ALERT_STATUS_CLOSED = T.let(proto_enum_name(AlertStatusProto, :ALERT_STATUS_CLOSED), String)
  ALERT_STATUS_REVIEW_REQUESTED = T.let(proto_enum_name(AlertStatusProto, :ALERT_STATUS_REVIEW_REQUESTED), String)
  ALERT_STATUS_REVIEW_DENIED = T.let(proto_enum_name(AlertStatusProto, :ALERT_STATUS_REVIEW_DENIED), String)

  ALERT_STATUS_TO_REQUEST_STATUS = T.let({
    ALERT_STATUS_CLOSED => ReviewComments::DelegatedDismissalRequest::RequestStatus::Approved,
    ALERT_STATUS_REVIEW_DENIED => ReviewComments::DelegatedDismissalRequest::RequestStatus::Rejected,
  }.freeze, T::Hash[String, ReviewComments::DelegatedDismissalRequest::RequestStatus])

  # Closure reason string values derived from closure_reason.proto
  CLOSURE_REASON_AMENDMENT = T.let(proto_enum_name(ClosureReasonProto, :CLOSURE_REASON_AMENDMENT), String)
  CLOSURE_REASON_PRIVATE_PACKAGE = T.let(proto_enum_name(ClosureReasonProto, :CLOSURE_REASON_PRIVATE_PACKAGE), String)
  CLOSURE_REASON_INACCURATE_LICENSE = T.let(proto_enum_name(ClosureReasonProto, :CLOSURE_REASON_INACCURATE_LICENSE), String)
  CLOSURE_REASON_POLICY_EDITED = T.let(proto_enum_name(ClosureReasonProto, :CLOSURE_REASON_POLICY_EDITED), String)
  CLOSURE_REASON_FIXED = T.let(proto_enum_name(ClosureReasonProto, :CLOSURE_REASON_FIXED), String)

  CLOSURE_REASON_TO_LABEL = T.let({
    CLOSURE_REASON_AMENDMENT => "amendment",
    CLOSURE_REASON_PRIVATE_PACKAGE => "private package",
    CLOSURE_REASON_INACCURATE_LICENSE => "inaccurate license",
    CLOSURE_REASON_POLICY_EDITED => "policy edited",
    CLOSURE_REASON_FIXED => "fixed",
  }.freeze, T::Hash[String, String])

  # controls if the "Close alert" button is enabled
  sig { override.params(user: User, comment: T.nilable(AutomatedReviewComment)).returns(T::Boolean) }
  def can_dismiss?(user:, comment: nil)
    return false unless FeatureFlag.vexi.enabled?(:dependency_graph_license_alert_closure, @repository, @repository.owner, @repository.business, default: false)
    return false unless Permissions::LicensePolicy.can_request_license_compliance_alert_dismissal?(user, @repository)

    return true if comment.nil?

    alert_status = comment.metadata&.dig(METADATA_KEY_ALERT_STATUS)
    alert_status.nil? || alert_status == ALERT_STATUS_OPEN || alert_status == ALERT_STATUS_REVIEW_DENIED
  end

  # NOTE: dismiss is not used in the current flow — delegated_dismissal_enabled? routes to request_dismissal instead.
  # dismiss! on the model sets dismissed_at and resolves the conversation, which we don't want until the alert is
  # actually closed by the license compliance remediation flow.
  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss(comment:, user:, reason:, resolution_note:)
    raise NotImplementedError, "License compliance comments use delegated dismissal. Use request_dismissal instead."
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def request_dismissal(comment:, user:, reason:, resolution_note:)
    raise AutomatedReviewComment::ArgumentError, "Invalid reason: #{reason}" unless DependencyGraph::LicenseComplianceDismissalOptions.valid_dismissal_reason?(reason)

    closure_reason = DependencyGraph::LicenseComplianceDismissalOptions.closure_reason_for(reason)
    raise AutomatedReviewComment::ArgumentError, "No closure reason mapping for: #{reason}" if closure_reason.nil?

    alert_id = Integer(comment.resource_id)

    response = OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new.request_alert_dismissal_by_id(
      alert_id: alert_id,
      user_id: user.id,
      closure_reason: closure_reason,
      comment: resolution_note
    )

    unless response.success
      raise AutomatedReviewComment::UnprocessableError, "Failed to request dismissal for license compliance alert #{alert_id}"
    end
  end

  # Returning true enables the status message UI.
  # The "Close alert" button remains disabled because can_dismiss? returns false.
  sig { override.returns(T::Boolean) }
  def dismissable?
    true
  end

  # When true routes to request_dismissal which is the review request flow for license compliance alerts
  sig { override.returns(T::Boolean) }
  def delegated_dismissal_enabled?
    true
  end

  sig { override.returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    DependencyGraph::LicenseComplianceDismissalOptions::DISMISSAL_OPTIONS
  end

  # Extracts actor, alert status, and closure reason from the comment's metadata and builds
  # a DelegatedDismissalRequest to display the alert status in the UI.
  sig do
    override.params(
      comment: AutomatedReviewComment
    ).returns(T.nilable(ReviewComments::DelegatedDismissalRequest))
  end
  def current_delegated_dismissal_request(comment:)
    metadata = comment.metadata
    # For recently opened alerts, metadata is empty and we return nil (no status message).
    return nil if metadata.nil? || metadata.empty?
    # Do not display a status message for alerts that have transitioned to open.
    alert_status = metadata[METADATA_KEY_ALERT_STATUS]
    return nil if alert_status.nil? || alert_status == :ALERT_STATUS_OPEN

    actor_id = metadata[METADATA_KEY_ACTOR_ID]
    actor = actor_id ? User.find_by(id: actor_id) : nil
    return nil if actor.nil?

    status = delegated_dismissal_request_status(alert_status: alert_status)
    reason = closure_reason(metadata[METADATA_KEY_CLOSURE_REASON])

    # Build a DelegatedDismissalRequest for the AutomatedReviewComment's delegatedDismissalRequest prop.
    # We do this for both alerts closed via review request and alerts closed directly (by a license policy manager
    # or bot), since both will have metadata populated with actor, status and closure reason.
    ReviewComments::DelegatedDismissalRequest.new(
      requester: actor,
      reason: reason,
      status: status,
      reviewer: nil # Not used to render the status message
    )
  end

  sig do
    params(
      alert_status: String
    ).returns(ReviewComments::DelegatedDismissalRequest::RequestStatus)
  end
  def delegated_dismissal_request_status(alert_status:)
    ALERT_STATUS_TO_REQUEST_STATUS.fetch(alert_status, ReviewComments::DelegatedDismissalRequest::RequestStatus::Pending)
  end

  sig do
    params(
      closure_reason: T.nilable(String)
    ).returns(String)
  end
  def closure_reason(closure_reason)
    return "amendment" if closure_reason.nil?

    CLOSURE_REASON_TO_LABEL.fetch(closure_reason, "amendment") # TODO (@ashelytc): Remove default once we allow requesters/reviewers to give closure reason in dialog.
  end

end
