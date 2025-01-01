# typed: true
# frozen_string_literal: true

class Businesses::InvitationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :user

  def organization_count
    @org_count ||= business.organizations_for_member(user).count
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def installation_count
    @installation_count ||= business_user_account&.enterprise_installation_user_accounts&.count.to_i
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def collaborator_repo_count
    @collaborator_repo_count ||= user.outside_collaborator_repositories(business: business).count
  end

  def business_user_account
    @business_user_account ||= business.business_user_account_for(user)
  end
end
