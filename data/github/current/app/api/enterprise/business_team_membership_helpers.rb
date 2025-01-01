# typed: strict
# frozen_string_literal: true

module Api::Enterprise::BusinessTeamMembershipHelpers
  extend T::Helpers

  requires_ancestor { Api::EnterpriseTeamMemberships }

  sig { params(enterprise: Business).returns(String) }
  def list_business_team_memberships(enterprise)
    team = find_business_team!
    members_list = team.members.order(:id)
    members = paginate_rel(members_list)

    deliver :user_hash, members, status: 200
  end

  sig { params(enterprise: Business).returns(String) }
  def get_business_team_membership!(enterprise)
    team = find_business_team!(error_options: base_error_config)

    # Checks if user is part of the enterprise
    user = validate_user!(enterprise, params[:username])

    # Checks if user is part of the team
    unless team.member?(user)
      deliver_error! 404, **base_error_config, message: "User is not a member of the team."
    end

    deliver :user_hash, user, status: 200
  end

  sig { params(enterprise: Business).returns(String) }
  def create_business_team_membership!(enterprise)
    team = find_business_team!
    user = EnterpriseTeams::Helper.validate_user_parameter(enterprise, params[:username])

    deliver_error! 422, **base_error_config, message: "Unable to add member to a team managed by an external group." if team.externally_managed?
    deliver_error! 400, **base_error_config, message: "Unable to add member because the team is at capacity." if team.members.count + 1 > enterprise.business_team_member_limit
    deliver_error! 400, **base_error_config, message: "Unable to add member because they are already a member." if team.member_ids.include?(user.id)

    status = team.add_member(user, caller_type: :business_team)
    deliver_error! 422, **base_error_config, message: status.business_message if status.error?

    deliver :user_hash, user, status: 201
  rescue ArgumentError => e
    deliver_error! 400, **base_error_config, message: e.message
  rescue EnterpriseTeams::Helper::UserNotInEnterpriseError => e
    deliver_error! 404, **base_error_config, message: e.message
  end

  sig { params(enterprise: Business).returns(String) }
  def bulk_create_business_team_memberships!(enterprise)
    team = find_business_team!

    data = receive(Hash)
    usernames = validate_usernames!(data.fetch("usernames", []))

    deliver_error! 422, **base_error_config, message: "Unable to add members to a team managed by an external group." if team.externally_managed?
    deliver_error! 400, **base_error_config, message: "Unable to add members because the team is at capacity." if team.members.count + usernames.count > enterprise.business_team_member_limit

    users = bulk_validate_users!(team.business, usernames, team)
    with_write do
      status = team.bulk_add_members(users, caller_type: :business_team)
      deliver_error! 422, **base_error_config, message: status.business_message if status.error?
    end

    deliver :user_hash, users, status: 200
  rescue ArgumentError => e
    deliver_error! 400, **base_error_config, message: e.message
  rescue EnterpriseTeams::Helper::UserNotInEnterpriseError => e
    deliver_error! 404, **base_error_config, message: e.message
  end

  sig { params(enterprise: Business, username: String).void }
  def delete_business_team_membership!(enterprise:, username:)
    team = find_business_team!(error_options: base_error_config)
    deliver_error! 422, **base_error_config, message: "Unable to remove member from a team managed by an external group." if team.externally_managed?

    user = validate_user!(enterprise, username)

    unless team.member?(user)
      deliver_error! 404, **base_error_config, message: "User is not a member of the team."
    end

    begin
      team.remove_member(user, caller_type: :business_team)
    rescue ActiveRecord::RecordNotDestroyed
      deliver_error! 422, **base_error_config, message: "Unable to remove member from the team."
    end

    deliver_empty status: 204
  end

  sig { params(enterprise: Business).returns(String) }
  def bulk_delete_business_team_memberships!(enterprise)
    team = find_business_team!(error_options: base_error_config)
    deliver_error! 422, **base_error_config, message: "Unable to delete members from a team managed by an external group." if team.externally_managed?

    data = receive(Hash)
    usernames = validate_usernames!(data.fetch("usernames", []))
    users = bulk_validate_users_for_removal!(enterprise, usernames, team)

    team.bulk_remove_members(users: users, caller_type: :business_team)

    deliver :user_hash, users, status: 200
  rescue ArgumentError => e
    deliver_error! 400, **base_error_config, message: e.message
  rescue EnterpriseTeams::Helper::UserNotInEnterpriseError => e
    deliver_error! 404, **base_error_config, message: e.message
  rescue ActiveRecord::RecordNotDestroyed
    deliver_error! 422, **base_error_config, message: "Unable to remove members from the team."
  end

  private

  sig { params(usernames: T.nilable(T::Array[String])).returns(T::Array[String]) }
  def validate_usernames!(usernames)
    if !usernames.is_a?(Array) || usernames.any? { |u| !u.is_a?(String) || u.empty? }
      deliver_error! 422, **base_error_config, message: "Invalid 'usernames' parameter."
    end

    if usernames.count > 100
      deliver_error! 400, **base_error_config, message: "Too many usernames provided. Maximum is 100."
    end

    usernames
  end

  sig { params(business: Business, usernames: T::Array[String], team: BusinessTeam).returns(T::Array[User]) }
  def bulk_validate_users!(business, usernames, team)
    users = EnterpriseTeams::Helper.bulk_validate_user_parameters(business, usernames)
    user_ids_set = users.map(&:id).to_set
    if team.member_ids.any? { |id| user_ids_set.include?(id) }
      deliver_error! 400, **base_error_config, message: "One or more users are already members of the team."
    end

    users.to_a
  end

  sig { params(business: Business, usernames: T::Array[String], team: BusinessTeam).returns(T::Array[User]) }
  def bulk_validate_users_for_removal!(business, usernames, team)
    users = EnterpriseTeams::Helper.bulk_validate_user_parameters(business, usernames)
    user_ids_set = users.map(&:id).to_set

    # Checks if any user is NOT a member of the team
    if !(user_ids_set - Set.new(team.member_ids)).empty?
      deliver_error! 400, **base_error_config, message: "One or more users are not members of the team."
    end

    users.to_a
  end
end
