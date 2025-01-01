# typed: true
# frozen_string_literal: true

class Orgs::People::PendingInvitationsPageView < Orgs::OverviewView
  INVITATIONS_PER_PAGE = 30

  attr_reader :organization, :page, :query, :role

  def page_title
    "People · #{organization.safe_profile_name}"
  end

  def invitations
    return @invitations if defined?(@invitations)

    scope = organization.pending_invitations.except_with_role(:billing_manager).with_valid_role

    query = people_query
    cleaned_query = query.cleaned_query

    scope = scope.like_login_or_profile_name_or_email(cleaned_query) if cleaned_query.present?
    scope = scope.with_invitation_source(query.invitation_source) if query.invitation_source.present?

    # Use feature flag for enterprise revamp improvements to translate reinstate to actual role
    scope = add_order_by_scope(scope, query)
      .limit(OrganizationInvitation::PENDING_INVITATIONS_QUERY_LIMIT)

    reinstate_user_ids = scope
      .filter_map { |org_invite| org_invite.invitee.id if org_invite.invitee.present? && org_invite.role == "reinstate" }
    restorable_admin_ids = Restorable::OrganizationUser.restorable_memberships(organization, reinstate_user_ids)
      .select { |membership| membership.subject_type == "Organization" }
      .group_by(&:user_id)
      .map { |_, memberships| memberships.max_by(&:id) }
      .filter_map { |membership| membership.user_id if membership.action == Ability::ACTION_RANKING[:admin] }

    scope = scope.map do |org_invite|
      if org_invite.role == "reinstate"
        if org_invite.invitee.present? && restorable_admin_ids.include?(org_invite.invitee.id)
          org_invite.role = "admin"
        else
          org_invite.role = "direct_member"
        end
      end
      org_invite
    end

    if query.role.present?
      role = query.role
      role = :admin if role == :owner
      scope = scope.select { |org_invite| org_invite.role == role.to_s }
    end

    @invitations = scope.paginate(page: page, per_page: INVITATIONS_PER_PAGE)
  end

  def add_order_by_scope(scope, query)
    sort_field = query.sort_field || :created
    sort_direction = query.sort_direction || :desc
    case sort_field
    when :title
      scope.order_by_title(sort_direction)
    when :created
      sort_direction = sort_direction == :asc ? "ASC" : "DESC"
      scope.order(Arel.sql("created_at #{sort_direction}, id #{sort_direction}"))
    end
  end

  def total_count
    @invitations.length
  end

  def show_admin_stuff?
    organization.adminable_by?(current_user)
  end

  def invitations_empty?
    invitations.empty?
  end

  def direct_or_team_member?
    return @direct_or_team_member if defined?(@direct_or_team_member)
    @direct_or_team_member = organization.direct_or_team_member?(current_user)
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def role_filter_select_class(filter)
    "selected" if role_filter_selected == filter
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def invitation_source_filter_select_class(filter)
    "selected" if invitation_source_filter_selected == filter
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def sort_filter_select_class(sort_field, sort_direction)
    "selected" if sort_field_filter_selected == sort_field && sort_direction_filter_selected == sort_direction
  end

  # Returns a Symbol for the queried role.
  def role_filter_selected
    @role_filter_selected ||= people_query.role_match || :all
  end

  # Returns a Symbol for the queried invitation source.
  def invitation_source_filter_selected
    @invitation_source_filter_selected ||= people_query.invitation_source_match || :all
  end

  # Returns a Symbol for the queried sort field.
  def sort_field_filter_selected
    @sort_field_filter_selected ||= people_query.sort_field_match || :created
  end

  # Returns a Symbol for the queried sort direction.
  def sort_direction_filter_selected
    @sort_direction_filter_selected ||= people_query.sort_direction_match || :desc
  end

  def people_query
    @people_query ||= Organization::People::Query.new(
      query: query,
      organization: organization,
      current_user: current_user,
      role: role
    )
  end
end
