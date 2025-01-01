# typed: true
# frozen_string_literal: true

# A class to encapsulate logic around parsing queries for finding members in
# organizations
class Organization::People::Query
  TWO_FACTOR_DISABLED_QUERY = "two-factor:disabled"
  TWO_FACTOR_ENABLED_QUERY = "two-factor:enabled"
  TWO_FACTOR_REQUIRED_QUERY = "two-factor:required"
  EXTERNAL_IDENTITY_LINKED_QUERY = "sso:linked"
  EXTERNAL_IDENTITY_UNLINKED_QUERY = "sso:unlinked"
  ORGANIZATION_MEMBERSHIP_GROUP_QUERY = "membership:external_group"
  ORGANIZATION_MEMBERSHIP_ADMIN_QUERY = "membership:admin"
  ROLE_QUERY = /role:(?<role_name>owner|member|guest_collaborator)/
  INVITATION_SOURCE_QUERY = /source:(?<invitation_source>member|scim)/
  SORT_QUERY = /sort:(?<sort_field>created|title)_(?<sort_direction>asc|desc)/

  attr_reader :query,
              :organization,
              :current_user,
              :role,
              :invitation_source,
              :sort_field,
              :sort_direction

  # - query: String. The raw string coming directly from the user.
  #
  # - organization: Orgnanization. The organization the user is searching.
  #
  # - current_user: User. The one doing the searching.
  #
  # - role: Symbol. The role in the organization the user is optionally
  # filtering for
  def initialize(query:, organization:, current_user:, role:)
    @query = query.to_s
    @organization = organization
    @current_user = current_user
    @role = role
  end

  # Public: Returns the query with filters (like "two-factor:disabled") stripped
  # out.
  #
  # Returns: String.
  def cleaned_query
    @cleaned_query ||= begin
      query
        .then(&method(:remove_known_query_matches))
        .then(&method(:set_role_value))
        .then(&method(:set_invitation_source_value))
        .then(&method(:set_sort_field_value))
        .then(&method(:set_sort_direction_value))
        .then(&method(:sanitize))
    end
  end

  # Public: Does the query contain an acutal search or are we just filtering?
  #
  # Returns: Boolean.
  def searching?
    cleaned_query.present?
  end

  # Public: What is the role, if any, the user is filtering for?
  #
  # Returns: Symbol.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def role_match
    @role_match ||= (match = query.match(ROLE_QUERY)) && match[:role_name].to_sym
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Public: What is the invitation source, if any, the user is filtering for?
  #
  # Returns: Symbol.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def invitation_source_match
    @invitation_source_match ||= (match = query.match(INVITATION_SOURCE_QUERY)) && match[:invitation_source].to_sym
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Public: What is the sort field, if any, the user is requesting?
  #
  # Returns: Symbol.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def sort_field_match
    @sort_field_match ||= (match = query.match(SORT_QUERY)) && match[:sort_field].to_sym
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Public: What is the sort direction, if any, the user is requesting?
  #
  # Returns: Symbol.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def sort_direction_match
    @sort_direction_match ||= (match = query.match(SORT_QUERY)) && match[:sort_direction].to_sym
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Public: Is the user filtering for two factor disabled members?
  #
  # Returns: Boolean.
  def two_factor_disabled_scope?
    query.include?(TWO_FACTOR_DISABLED_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering for two factor enabled members?
  #
  # Returns: Boolean.
  def two_factor_enabled_scope?
    query.include?(TWO_FACTOR_ENABLED_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering for two factor required members?
  #
  # Returns: Boolean.
  def two_factor_required_scope?
    query.include?(TWO_FACTOR_REQUIRED_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering for organization membership added to an external group members?
  #
  # Returns: Boolean.
  def organization_membership_group_scope?
    query.include?(ORGANIZATION_MEMBERSHIP_GROUP_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering for organization membership added by admin members?
  #
  # Returns: Boolean.
  def organization_membership_admin_scope?
    query.include?(ORGANIZATION_MEMBERSHIP_ADMIN_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering members with linked external identities?
  #
  # Returns: Boolean.
  def external_identity_linked_scope?
    query.include?(EXTERNAL_IDENTITY_LINKED_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user filtering members with unlinked external identities?
  #
  # Returns: Boolean.
  def external_identity_unlinked_scope?
    query.include?(EXTERNAL_IDENTITY_UNLINKED_QUERY) &&
      org_adminable_by_current_user?
  end

  # Public: Is the user an organization member, filtering by role?
  #
  # Returns: Boolean.
  def role_scope?
    role_match && organization.member?(current_user)
  end

  private

  def org_adminable_by_current_user?
    return @user_is_admin if defined?(@user_is_admin)
    @user_is_admin = @organization.adminable_by?(@current_user)
  end

  def remove_known_query_matches(query)
    query
      .gsub(TWO_FACTOR_DISABLED_QUERY, "")
      .gsub(TWO_FACTOR_ENABLED_QUERY, "")
      .gsub(TWO_FACTOR_REQUIRED_QUERY, "")
      .gsub(EXTERNAL_IDENTITY_LINKED_QUERY, "")
      .gsub(EXTERNAL_IDENTITY_UNLINKED_QUERY, "")
      .gsub(ORGANIZATION_MEMBERSHIP_GROUP_QUERY, "")
      .gsub(ORGANIZATION_MEMBERSHIP_ADMIN_QUERY, "")
      .gsub(ROLE_QUERY, "")
      .gsub(INVITATION_SOURCE_QUERY, "")
      .gsub(SORT_QUERY, "")
      .strip
  end

  def set_role_value(query)
    if role_match
      @role = role_match
      @role = :direct_member if @role == :member
    end

    query
  end

  def set_invitation_source_value(query)
    if invitation_source_match
      @invitation_source = invitation_source_match
    end

    query
  end

  def set_sort_field_value(query)
    if sort_field_match
      @sort_field = sort_field_match
    end

    query
  end

  def set_sort_direction_value(query)
    if sort_direction_match
      @sort_direction = sort_direction_match
    end

    query
  end

  def sanitize(query)
    ActiveRecord::Base.sanitize_sql_like(query)
  end
end
