# typed: true
# frozen_string_literal: true

# A class to encapsulate logic around searching for members of an
# organization.
class Organization::People::Search
  # - query: Query. The parsed user input.
  #
  # - users: ActiveRecord::Relation. A scope of Users filtered based on the user
  # input.
  def initialize(query:, users:)
    @query = query
    @users = users
  end

  # Public: Search for members (with SQL LIKE) based on the query the user supplied. If there is
  # no query string, then just return org members matching the filter criteria.
  #
  # Return: ActiveRecord::Relation of Users.
  def call
    return org_members unless @query.searching?

    org_members
      .includes(:profile)
      .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{@query.cleaned_query}%" }])
      .references(:profile)
  end

  private

  def org_members
    @users.where(id: org_member_ids)
  end

  def org_member_ids
    @query.organization.visible_user_ids_for(
      @query.current_user,
      type: visibility_level,
      limit: Organization::MEGA_ORG_MEMBER_THRESHOLD,
      include_indirect_abilities: true
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
