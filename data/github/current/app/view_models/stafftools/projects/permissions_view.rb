# typed: true
# frozen_string_literal: true

class Stafftools::Projects::PermissionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :project
  attr_reader :page
  attr_reader :per_page

  def ability_for(user)
    @abilities ||= Hash.new do |hash, key|
      hash[key] = Authorization.service.most_capable_ability_between(actor: key, subject: project)
    end

    @abilities[user]
  end

  def users_with_access
    return @users_with_access if defined?(@users_with_access)

    user_ids = Team.members_of(team_abilities, immediate_only: false).pluck(:id)
    user_ids += collaborator_abilities

    if project.owner.is_a?(Organization)
      user_ids += project.owner.admin_ids
      user_ids += project.owner.member_ids if project.org_permission
    end

    @users_with_access = User.where(id: user_ids.uniq).order("login ASC").paginate(page: page, per_page: per_page)
  end

  def project_label
    if project.public?
      if GitHub.public_repositories_available?
        "public"
      else
        "internal"
      end
    else
      "private"
    end
  end

  private

  def collaborator_abilities
    @collaborator_abilities ||= Ability.where(
      actor_type: "User",
      subject_id: project.id,
      subject_type: "Project",
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id)
  end

  def team_abilities
    @team_abilities ||= Ability.teams_direct_on_projects(
      project_id: project.id,
    ).pluck(:actor_id)
  end
end
