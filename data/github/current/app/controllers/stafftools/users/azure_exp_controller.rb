# typed: true
# frozen_string_literal: true

class Stafftools::Users::AzureExpController < StafftoolsController
  extend T::Sig

  include Stafftools::Users::ControllerLayoutMethods

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show, :destroy]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  before_action :dotcom_required
  before_action :ensure_user_exists
  before_action :ensure_is_not_organization

  layout :overview_layout

  def show
    render "stafftools/users/azure_exp/index", locals: { user: this_user, assignment_namespaces: remote_assignment_namespaces }
  end

  def destroy
    if params["namespace"].blank?
      flash[:error] = "Please provide the Experiment namespace"
      return redirect_to stafftools_user_overview_path(this_user)
    end

    begin
      AzureEXP::ExpAssignmentProvider.new(participant:, namespace: params["namespace"]).clear_exp_cache
      flash[:notice] = "Cleared ExP cache for #{this_user}"
    rescue GitHub::KV::UnavailableError
      flash[:error] = "Could not clear ExP cache for #{this_user}"
      return redirect_to stafftools_user_overview_path(this_user)
    end

    redirect_to stafftools_user_path(this_user)
  end

  private

  memoize def post_params
    params.permit(:namespace, :experiment, :variant)
  end

  sig { returns(T::Array[String]) }
  memoize def remote_assignment_namespaces
    AzureEXP::ExpAssignmentProvider
      .new(participant:, namespace: nil)
      .assignment_namespaces
  end

  memoize def participant
    AzureEXP::Beta::Participant.from_user(this_user)
  end

  def ensure_is_not_organization
    render plain: "unable to interact with Azure ExP for an organization", status: :bad_request if this_user.organization?
  end
end
