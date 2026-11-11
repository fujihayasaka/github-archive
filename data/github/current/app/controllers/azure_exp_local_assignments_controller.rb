# typed: true
# frozen_string_literal: true

class AzureExpLocalAssignmentsController < ApplicationController
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    only: [:show, :edit, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  before_action :dotcom_required
  before_action :employee_only
  before_action :ensure_user_exists, only: [:show]

  def show
    render partial: "stafftools/users/azure_exp/experiments", locals: { user: user, namespaces: namespaces_for(user) }
  end

  # can only edit your own user record as a staff
  def edit
    render partial: "stafftools/users/azure_exp/experiments", locals: { user: current_user, namespaces: current_participant.namespaces, editable: true }
  end

  def update
    AzureEXP::Beta::LocalAssignmentService.assign_variant(
      participant: AzureEXP::Beta::Participant.from_user(current_user),
      namespace: params[:namespace],
      experiment: params[:experiment],
      variant: params[:variant]
    )

    render partial: "stafftools/users/azure_exp/experiments", locals: { user: current_user, namespaces: current_participant.namespaces, editable: true }
  end

  private

  def namespaces_for(user)
    AzureEXP::Beta::Participant.from_user(user).namespaces
  end

  def current_participant
    AzureEXP::Beta::Participant.from_user(current_user)
  end

  def user
    User.find_by_login(params[:user])
  end

  def ensure_user_exists
    render_404 if user.nil?
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
