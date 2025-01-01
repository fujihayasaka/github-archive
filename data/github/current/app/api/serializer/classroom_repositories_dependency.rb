# typed: true
# frozen_string_literal: true

module Api::Serializer::ClassroomRepositoriesDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::AvatarsDependency }

  # Creates a Hash to be serialized to JSON.
  #
  # repo    - Repository instance.
  # options - Hash
  #           :full - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the Repository exists, or nil.
  def classroom_repository_hash(repo, options = {})
    return nil if !repo
    options = Api::SerializerOptions.fill(options)
    repo_api_path = "/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}"
    url = url(repo_api_path, options)

    # Fix for #37741. These attributes require a routed repo, but since
    # this serializer method is used in lists, we can't just bail on the
    # whole repo.
    default_branch = begin
      repo.default_branch
    rescue GitRPC::RepositoryOffline => boom
      Failbot.push app: "github-unrouted"
      Failbot.report boom
      if repo.fork?
        repo.parent.default_branch
      elsif repo.template_repository_clone
        repo.template_repository_clone.template_repository.default_branch
      else
        repo.owner_default_new_repo_branch
      end
    end

    {
      id: repo.id,
      name: repo.name,
      full_name: repo.full_name,
      owner: basic_user_hash(repo.owner, content_options(options)),
      private: repo.private?,
      description: repo.description,
      url: url,
      clone_url: repo.clone_url,
      commits_url: url("#{repo_api_path}/commits{/sha}", options),
      pulls_url: url("#{repo_api_path}/pulls{/number}", options),
      teams_url: url("#{repo_api_path}/teams", options),
      language: repo.primary_language_name,
      size: repo.disk_usage.to_i,
      default_branch: default_branch,
      open_issues_count: repo.open_issues_count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      is_template: repo.template?,
      archived: repo.archived?,
      disabled: repo.disabled?,
      visibility: repo.visibility,
      pushed_at: time(repo.pushed_at),
      created_at: time(repo.created_at),
      updated_at: time(repo.updated_at),
      classroom_assignment: assignment_hash(repo, options)
    }
  end

  def assignment_hash(repo, options = {})
    assignment = ClassroomRepository.find_by(repository_id: repo.id)
    return nil unless assignment

    {
      classroom_name: assignment.classroom_name,
      classroom_id: assignment.classroom_id,
      assignment_name: assignment.assignment_name,
      assignment_id: assignment.assignment_id,
      assignment_type: assignment.assignment_type,
      deadline: assignment.deadline,
      admins: create_admin_hash(assignment, options),
      team_id: assignment.team_id,
      team_members: create_team_member_hash(assignment, options)
    }
  end

  private

  def create_admin_hash(assignment, options)
    admins = assignment.classroom&.instructors || []

    admins.map do |admin|
      basic_user_hash(admin.classroom_user.user, options)
    end
  end

  def create_team_member_hash(assignment, options)
    team_members = Team.members_of(assignment.team_id) || []

    team_members.map do |user|
      basic_user_hash(user, options)
    end
  end

  def basic_user_hash(user, options)
    return unless user

    # login_for_api takes precedence therefore safe to use login here.
    {
      login: user.login_for_api(use: options[:serialize_login]) || user.login, # rubocop:disable GitHub/DoNotAllowLogin
      id: user.id,
      avatar_url: avatar(user),
      email: user_email(user, options)
    }
  end

  def user_email(user, options)
    email = user.email_roles.public.includes(:email).first&.email&.email

    email ? email : StealthEmail.new(user).email
  end
end
