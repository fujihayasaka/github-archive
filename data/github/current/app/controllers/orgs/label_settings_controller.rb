# typed: true
# frozen_string_literal: true

class Orgs::LabelSettingsController < Orgs::Controller

  include Issues::RateLimitsDependency

  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

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

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    optional: false, only: [:preview]

  def create
    name = label_params[:name]
    color = label_params[:color]&.delete("#") # Strip any CSS-style hex codes
    description = label_params[:description]

    label = current_organization.user_labels.create(name: name,
                                                    color: color,
                                                    description: description)
    respond_to do |format|
      format.html do
        if request.xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          else
            render partial: "orgs/label_settings/label", object: label
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def update
    return head(:not_found) unless label = current_organization.user_labels.find_by_id(params[:id])

    color = label_params[:color]&.delete("#") # Strip any CSS-style hex codes
    label.name = label_params[:name] if label_params[:name]
    label.color = color if color
    label.description = label_params[:description]

    label.save

    respond_to do |format|
      format.html do
        if request.xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          else
            render partial: "orgs/label_settings/label", object: label
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def destroy
    label = current_organization.user_labels.find_by_id(params[:id])
    label.destroy if label
    if request.xhr?
      head(label ? 200 : 404)
    else
      redirect_to :back
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    label = current_organization.user_labels.find_by_id(params[:id]) if params[:id].present?
    label ||= current_organization.user_labels.new

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
        render partial: "orgs/label_settings/preview", locals: { label: label }, layout: false
      end
    end
  end

  private

  def label_params
    params.require(:label).permit(:name, :color, :description)
  end
end
