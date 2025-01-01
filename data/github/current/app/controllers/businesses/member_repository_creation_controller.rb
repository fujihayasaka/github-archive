# typed: true
# frozen_string_literal: true

class Businesses::MemberRepositoryCreationController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  NO_POLICY_VALUE = "no_policy"
  DISABLED_VALUE = "disabled"
  ALLOWED_VALUE = "allowed"
  ALL_VALUES = [NO_POLICY_VALUE, DISABLED_VALUE, ALLOWED_VALUE].freeze

  def update
    members_can_create_repositories = members_can_create_repos_params[:members_can_create_repositories]
    validate_setting value: members_can_create_repositories, valid_values: ALL_VALUES

    enabled_visibilities = case members_can_create_repositories
    when NO_POLICY_VALUE
      this_business.clear_members_can_create_repositories(actor: current_user)
    when DISABLED_VALUE
      this_business.allow_members_can_create_repositories_with_visibilities(
        force: true,
        actor: current_user,
        public_visibility: false,
        private_visibility: false,
        internal_visibility: false,
      )
    when ALLOWED_VALUE
      this_business.allow_members_can_create_repositories_with_visibilities(
        force: true,
        actor: current_user,
        public_visibility: members_can_create_repos_params[:public] == "true",
        private_visibility: members_can_create_repos_params[:private] == "true",
        internal_visibility: members_can_create_repos_params[:internal] == "true",
      )
    end

    message = if enabled_visibilities.nil?
      "Organization administrators can now change this setting for individual organizations."
    elsif enabled_visibilities.present?
      "Members can now create #{to_sentence(enabled_visibilities)} repositories."
    else
      "Members can no longer create repositories."
    end

    redirect_to :back, notice: message
  end

  private

  memoize def members_can_create_repos_params
    params.require(:business).permit(:members_can_create_repositories, :public, :private, :internal)
  end

  def to_sentence(arr)
    return arr.first if arr.length == 1

    string = arr[0..-2].join(", ")
    string += "," if arr.length > 2 # Oxford commas keep it classy
    string += " and "
    string += arr.last

    string
  end
end
