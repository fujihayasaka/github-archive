# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::BulkActionsController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include PullRequests::DatabaseSelection

  allow_verified_fetch only: [:create]

  before_action :parse_json_params
  before_action :validate_create_params, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    only: [:create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Ghui::ItemPickers::BulkActionsController#create"].freeze

  prepend_around_action :route_reads_to_replicas, only: [:create]

  def create
    input_params = {}

    if params[:clearMilestone].present?
      input_params["clearMilestone"] = ActiveModel::Type::Boolean.new.cast(params[:clearMilestone])
    elsif params[:milestoneId].present?
      input_params["milestoneId"] = params[:milestoneId]
    end

    if params[:clearIssueType].present?
      input_params["unsetIssueType"] = ActiveModel::Type::Boolean.new.cast(params[:clearIssueType])
    elsif params[:issueTypeId].present?
      input_params["issueTypeId"] = params[:issueTypeId]
    end

    if params[:addedLabelIds].present?
      input_params["applyLabelIds"] = params[:addedLabelIds].map(&:to_s)
    end

    if params[:removedLabelIds].present?
      input_params["removeLabelIds"] = params[:removedLabelIds].map(&:to_s)
    end

    if params[:addToProjectIds].present?
      input_params["addToProjectV2Ids"] = params[:addToProjectIds].map(&:to_s)
    end

    if params[:removeFromProjectIds].present?
      input_params["removeFromProjectV2Ids"] = params[:removeFromProjectIds].map(&:to_s)
    end

    if params[:applyAssigneeIds].present?
      input_params["applyAssigneeIds"] = params[:applyAssigneeIds].map(&:to_s)
    end

    if params[:removeAssigneeIds].present?
      input_params["removeAssigneeIds"] = params[:removeAssigneeIds].map(&:to_s)
    end

    input_params["ids"] = params[:ids].map(&:to_s)

    variables = { "input" => input_params }

    result = execute_server_persisted_query("UpdateIssuesBulk", variables: variables)
    return unless result

    respond_graphql_payload(result)
  end

  private

  def route_reads_to_replicas(&block)
    if FeatureFlag.vexi.enabled?(:web_read_from_replicas_controller, ControllerActor.new(self.class), default: false)
      use_replica_clusters([
        ApplicationRecord::Mysql1,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Ballast,
        ApplicationRecord::Memex,
      ], &block)
    else
      block.call
    end
  end

  def validate_create_params
    if params[:milestoneId].present? && params[:clearMilestone].present?
      respond_error(:bad_request, "Cannot provide both milestoneId and clearMilestone parameters")
      return
    end

    if params[:issueTypeId].present? && params[:clearIssueType].present?
      respond_error(:bad_request, "Cannot provide both issueTypeId and clearIssueType parameters")
      return
    end

    if params[:ids].present?
      validate_required_params(:ids)
    else
      respond_error(:bad_request, "ids parameter is required")
      return
    end

    # Validate that at least one operation is provided
    has_milestone_operation = params[:milestoneId].present? || params[:clearMilestone].present?
    has_issue_type_operation = params[:issueTypeId].present? || params[:clearIssueType].present?
    has_label_operation = params[:addedLabelIds].present? || params[:removedLabelIds].present?
    has_project_operation = params[:addToProjectIds].present? || params[:removeFromProjectIds].present?
    has_assignee_operation = params[:applyAssigneeIds].present? || params[:removeAssigneeIds].present?

    unless has_milestone_operation || has_issue_type_operation || has_label_operation || has_project_operation || has_assignee_operation
      respond_error(:bad_request, "At least one operation (milestone, issue type, labels, projects, or assignees) must be provided")
    end
  end

  memoize def repository
    return nil unless params[:ids].present?
    begin
      first_global_relay_id = params[:ids].first
      issue = typed_object_from_id([Platform::Objects::Issue], first_global_relay_id)
      issue&.repository
    rescue Platform::Errors::NotFound
      nil
    end
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  def target_for_conditional_access
    repository&.owner
  end
end
