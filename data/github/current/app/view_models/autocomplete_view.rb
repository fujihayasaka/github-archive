# typed: true
# frozen_string_literal: true

class AutocompleteView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :query, :organization, :with_orgs, :include_teams, :business,
    :org_members_only, :include_business_orgs, :orgs_only, :exclude_suspended, :prepend_friends,
    :include_outside_collaborators, :business_only, :with_businesses, :scope_businesses_to_ids

  delegate :allow_email_invites?, :email_invitation?, :suggestions,
    :suggestions?, :user_query?, :email_query?, to: :autocomplete_query

  def org_only_query?
    !!org_members_only
  end

  private

  def org_members_only?
    org_members_only
  end

  def autocomplete_query
    @autocomplete_query ||= AutocompleteQuery.new(
      current_user,
      query,
      organization: organization,
      include_teams: include_teams,
      business: business,
      businesses_only: business_only,
      with_businesses: with_businesses,
      scope_businesses_to_ids: scope_businesses_to_ids,
      org_members_only: org_members_only?,
      include_business_orgs: include_business_orgs,
      orgs_only: orgs_only,
      with_orgs: with_orgs,
      exclude_suspended: exclude_suspended,
      prepend_friends: prepend_friends,
      include_outside_collaborators: include_outside_collaborators
    )
  end
end
