# typed: true
# frozen_string_literal: true

class PullRequests::LabelsController < AbstractRepositoryController
  include LabelEducationHelper
  include Issues::RateLimitsDependency

  before_action :pushers_only
  before_action :writable_repository_required

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:preview]

  LABELS_PER_PAGE = 30

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  def create
    name = params[:label][:name]
    color = params[:label][:color]
    description = params[:label][:description]
    path  = gh_labels_path(current_repository)

    color.try(:delete!, "#") # Strip any CSS-style hex codes
    label = current_repository.labels.create(name: name, color: color,
                                             description: description)

    if label.persisted?
      issue_id = params[:issue_id] ? params[:issue_id].to_i : nil
      track_issue_edits_from_project_board(edited_fields: ["labels"])
    end

    respond_to do |wants|
      wants.html do
        if T.must(request).xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          elsif params[:return_label_list_item]
            subject_kind = if params[:return_label_list_item] == "discussion"
              :discussion
            else
              :issue
            end

            render partial: "issues/sidebar/label", locals: { label: label, selected: true, subject_kind: subject_kind }
          else
            render partial: "labels/label", object: label
          end
        else
          redirect_to(path)
        end
      end
    end
  end

  def update
    return head(:not_found) unless label = current_repository.labels.find_by_id(params[:id])

    color = params[:label][:color].try(:delete, "#") # Strip any CSS-style hex codes
    label.name = params[:label][:name] if params[:label][:name]
    label.color = color if color
    label.description = params[:label][:description]
    changes = label.changes

    label.save # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    respond_to do |wants|
      wants.html do
        if T.must(request).xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          else
            track_issue_edits_from_project_board(edited_fields: ["labels"])
            render partial: "labels/label", object: label
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    label = current_repository.labels.find_by_id(params[:id]) if params[:id].present?
    label ||= current_repository.labels.new

    label.name = params[:name]
    label.description = params[:description]
    label.color = params[:color]

    unless label.valid?
      json = label.errors.as_json(full_messages: true)
      json[:message] = label.errors.full_messages.join(", ")
      return render(json: json, status: :unprocessable_entity)
    end

    respond_to do |format|
      format.html do
        render partial: "labels/preview", locals: { label: label }, layout: false
      end
    end
  end
end
