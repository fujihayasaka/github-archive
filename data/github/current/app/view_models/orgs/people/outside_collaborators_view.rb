# typed: true
# frozen_string_literal: true

class Orgs::People::OutsideCollaboratorsView < Orgs::OverviewView
  include EnterpriseManagedUsersHelper

  TWO_FACTOR_DISABLED_QUERY = "two-factor:disabled"
  TWO_FACTOR_ENABLED_QUERY = "two-factor:enabled"
  TWO_FACTOR_REQUIRED_QUERY = "two-factor:required"

  # The amount of records to show per page
  PER_PAGE = 30

  # If there are more than this many pages of records, use next/prev links
  # instead of individual page links
  USE_NEXT_PREV_AFTER_PAGES = 50

  attr_reader :organization, :page, :query

  def page_title
    "#{outside_collaborators_verbiage(organization).titleize} · People · #{organization.safe_profile_name}"
  end

  def two_factor_enabled_for_user?(user)
    user.two_factor_authentication_enabled?
  end

  # Public: Whether or not the user is subject to an active account 2FA requirement.
  #
  # Returns a boolean.
  def user_has_active_account_two_factor_requirement?(user)
    user.in_account_2fa_requirement_required_state?
  end

  # Public: Whether or not the user is subject to a pending account 2FA requirement.
  #
  # Returns a boolean.
  def user_has_pending_account_two_factor_requirement?(user)
    !user.in_account_2fa_requirement_required_state? && user.has_forthcoming_account_two_factor_requirement?
  end

  # Public: The date on which account-base 2FA is required.
  #
  # Returns a Time in UTC.
  def user_account_two_factor_required_by_date(user)
    return nil unless user.has_forthcoming_account_two_factor_requirement?
    user.two_factor_requirement_metadata.required_by.utc
  end

  def outside_collaborators
    return @outside_collaborators if defined?(@outside_collaborators)

    scope = add_two_factor_scope(organization.outside_collaborators)

    if cleaned_query.present?
      scope = scope.like_login_or_profile_name(cleaned_query)
    end

    page_links_cutoff = USE_NEXT_PREV_AFTER_PAGES * PER_PAGE
    count_limit = [page, USE_NEXT_PREV_AFTER_PAGES].max * PER_PAGE + 1
    count = scope.limit(count_limit).count
    @has_too_many_pages = count > page_links_cutoff

    @outside_collaborators = scope.order(:login).paginate(page: page, per_page: PER_PAGE, total_entries: count)
  end

  def use_page_links?
    outside_collaborators # load data if not loaded
    !@has_too_many_pages
  end

  def repository_invitations_count
    @repository_invitations ||= organization.repository_invitations.size
  end

  def show_no_results?
    query.present? && no_outside_collaborators?
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def two_factor_filter_select_class(filter)
    "selected" if two_factor_filter_selected == filter
  end

  def show_repository_invitations?
    GitHub.repo_invites_enabled? && repository_invitations_count > 0
  end

  private

  def no_outside_collaborators?
    outside_collaborators.empty?
  end

  def add_two_factor_scope(scope)
    if two_factor_enabled_scope?
      scope
        .includes(:two_factor_credential)
        .where("two_factor_credentials.id IS NOT NULL")
        .references(:two_factor_credential)
    elsif two_factor_required_scope?
      required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:required, :warning, :interrupt).values
      scope
      .includes(:two_factor_credential, :two_factor_requirement_metadata)
      .references(:two_factor_credential, :two_factor_requirement_metadata)
      .where("two_factor_credentials.id IS NULL")
      .where("two_factor_requirement_metadata.id IS NOT NULL")
      .where("two_factor_requirement_metadata.state IN (?)", required_states)
    elsif two_factor_disabled_scope?
      not_required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:optional, :exempt).values
      scope
      .includes(:two_factor_credential, :two_factor_requirement_metadata)
      .references(:two_factor_credential, :two_factor_requirement_metadata)
      .where("two_factor_credentials.id IS NULL")
      .where("two_factor_requirement_metadata.id IS NULL or two_factor_requirement_metadata.state IN (?)", required_states)
    else
      scope
    end
  end

  def two_factor_disabled_scope?
    query.to_s.include?(TWO_FACTOR_DISABLED_QUERY) && organization.adminable_by?(current_user)
  end

  def two_factor_enabled_scope?
    query.to_s.include?(TWO_FACTOR_ENABLED_QUERY) && organization.adminable_by?(current_user)
  end

  def two_factor_required_scope?
    query.to_s.include?(TWO_FACTOR_REQUIRED_QUERY) && organization.adminable_by?(current_user)
  end

  # Returns the query with filters (like "two-factor:disabled") stripped out.
  def cleaned_query
    q = query.to_s
    [TWO_FACTOR_DISABLED_QUERY, TWO_FACTOR_ENABLED_QUERY, TWO_FACTOR_REQUIRED_QUERY].each do |filter|
      q = q.gsub(filter, "").strip
    end

    ActiveRecord::Base.sanitize_sql_like(q)
  end

  # Returns a Symbol for the selected 2FA scope queried.
  def two_factor_filter_selected
    @two_factor_filter_selected ||=
      case
      when two_factor_enabled_scope?
        :enabled
      when two_factor_disabled_scope?
        :disabled
      when two_factor_required_scope?
        :required
      else
        :all
      end
  end
end
