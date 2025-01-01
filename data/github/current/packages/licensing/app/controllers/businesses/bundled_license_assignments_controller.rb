# typed: true
# frozen_string_literal: true

class Businesses::BundledLicenseAssignmentsController < Businesses::BusinessController
  include BusinessesHelper
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch
  before_action :parse_json_params

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::BundledLicenseAssignmentsController#create",
    "Businesses::BundledLicenseAssignmentsController#destroy",
    "Businesses::BundledLicenseAssignmentsController#search",
    "Businesses::BundledLicenseAssignmentsController#update",
  ]
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,

  MIN_QUERY_LENGTH = 1

  # Endpoint is called from debounced user input in the UI. Returns records
  # that fuzzy match from the beginning of the `email` or `identity` (aka UPN) fields.
  def search # rubocop:todo GitHub/UseRestfulActions
    email_or_upn = params[:email_or_upn]&.strip

    if email_or_upn.blank? || email_or_upn.length < MIN_QUERY_LENGTH
      render json: { error: "Query must be at least #{MIN_QUERY_LENGTH} #{"character".pluralize(MIN_QUERY_LENGTH)} long" }, status: :bad_request
      return
    end

    # Downcase for case-insensitive search, and fuzzy match after the input string
    search = "#{email_or_upn.downcase}%"

    # Query executes in < 500ms for customer with most amount of bundled license assignments
    results = this_business.bundled_license_assignments
      .select(:id, :email, :identity)
      .nonrevoked
      .not_manual_match
      .where("email LIKE :search OR identity LIKE :search", search:) # rubocop:todo GitHub/DoNotUseLower
      .limit(10)

    render json: results, only: [:id, :email, :identity], root: false
  end

  def create
    user = BusinessUserAccount.where(business_id: this_business.id, user_id: params[:user_id]).first&.user

    if user.nil?
      render json: { error: "User not found" }, status: :not_found
      return
    end

    assignment = this_business
        .bundled_license_assignments
        .nonrevoked
        .find_by(id: params[:id])
    if assignment.nil?
      render json: { error: "Bundled license assignment not found" }, status: :not_found
      return
    end

    if assignment.user.present?
      render json: { error: "Bundled license assignment already has a user" }, status: :unprocessable_entity
    else
      if create_manual_assignment(assignment, user)
        render json: { success: true }, status: :ok
      else
        render json: { error: "Failed to assign user to bundled license" }, status: :unprocessable_entity
      end
    end
  end

  def update
    user = BusinessUserAccount.where(business_id: this_business.id, user_id: params[:user_id]).first&.user

    if user.nil?
      render json: { error: "User not found" }, status: :not_found
      return
    end

    assignment = this_business.bundled_license_assignments.nonrevoked.find_by(id: params[:id])
    if assignment.nil?
      render json: { error: "Bundled license assignment not found" }, status: :not_found
    elsif assignment.user.present? && !assignment.manual_match?
      render json: { error: "Bundled license assignment cannot be changed because it was automatically matched" }, status: :unprocessable_entity
    else
      unless remove_user_from_current_assignment(user)
        render json: { error: "Failed to dissociate user from prior assignment" }, status: :unprocessable_entity
        return
      end

      if create_manual_assignment(assignment, user)
        render json: { success: true }, status: :ok
      else
        render json: { error: "Failed to update user on bundled license" }, status: :unprocessable_entity
      end
    end
  end

  def destroy
    assignment = this_business.bundled_license_assignments.nonrevoked.find_by(id: params[:id])
    if assignment.nil?
      render json: { error: "Bundled license assignment not found" }, status: :not_found
    elsif assignment.user.nil?
      render json: { error: "Bundled license assignment does not have a user assigned" }, status: :unprocessable_entity
    elsif !assignment.manual_match?
      render json: { error: "Bundled license assignment cannot be removed because it was automatically matched" }, status: :unprocessable_entity
    else
      if assignment.unassign!
        render json: { success: true }, status: :ok
      else
        render json: { error: "Failed to remove user from bundled license" }, status: :unprocessable_entity
      end
    end
  end

  private

  # Assigns the user to the assignment
  def create_manual_assignment(assignment, user)
    assignment.user = user
    assignment.manual_match = true
    assignment.manual_match_at = Time.current
    assignment.save
  end

  # Dissociates the user from any prior assignment, allowing them to be assigned to a new one.
  def remove_user_from_current_assignment(user)
    prior_assignment = this_business.bundled_license_assignments.nonrevoked.find_by(user: user)
    if prior_assignment
      return prior_assignment.unassign!
    end
    true # Return true if no prior assignment exists
  end
end
