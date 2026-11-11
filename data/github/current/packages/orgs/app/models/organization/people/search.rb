# typed: true
# frozen_string_literal: true

# A class to encapsulate logic around searching for members of an
# organization.
class Organization::People::Search
  # Maximum number of results to return from Elasticsearch when searching.
  ES_SEARCH_LIMIT = 1000

  # - query: Query. The parsed user input.
  #
  # - users: ActiveRecord::Relation. A scope of Users filtered based on the user
  # input.
  def initialize(query:, users:)
    @query = query
    @users = users
  end

  # Public: Search for members based on the query the user supplied. Uses
  # Elasticsearch to find matching members across the entire org (no member
  # count cap). When not searching, returns all visible members restricted to
  # the first MEGA_ORG_MEMBER_THRESHOLD members.
  #
  # Return: ActiveRecord::Relation of Users.
  def call
    return org_members unless @query.searching?

    elasticsearch_org_member_search
  end

  private

  # Search for org members using Elasticsearch. This path has no member count
  # cap because ES indexes all org memberships via the all_org_ids /
  # public_org_ids fields.
  #
  # 1. Query ES for users matching the search text within the org.
  # 2. Validate the ES results through visible_user_ids_for (with actor_ids)
  #    to enforce role-based visibility without the 50K limit.
  # 3. Intersect with the Filter-produced @users scope to honor 2FA/SSO/etc.
  def elasticsearch_org_member_search
    org = @query.organization
    es_scope = org.limit_to_public_members?(@query.current_user) ? :public : :all

    es_users = User.user_query(
      @query.unsanitized_cleaned_query,
      org: org,
      org_member_scope: es_scope,
      limit: ES_SEARCH_LIMIT,
    )

    return @users.none if es_users.empty?

    es_user_ids = es_users.pluck(:id)
    visible_ids = org.visible_user_ids_for(
      @query.current_user,
      type: visibility_level,
      actor_ids: es_user_ids,
    )

    @users.where(id: visible_ids)
  end

  def org_members
    @users.where(id: org_member_ids)
  end

  def org_member_ids
    @query.organization.visible_user_ids_for(
      @query.current_user,
      type: visibility_level,
      limit: Organization::MEGA_ORG_MEMBER_THRESHOLD
    )
  end

  def visibility_level
    return :all unless  @query.role_scope?

    if @query.role == :owner
      :admin
    elsif @query.role == :direct_member
      :member_without_admin
    elsif @query.role == :guest_collaborator
      :guest_collaborator
    else
      :all
    end
  end
end
