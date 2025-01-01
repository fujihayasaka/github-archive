# typed: true
# frozen_string_literal: true

class Orgs::TeamMembersController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:archived_team_posts]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :archived_team_posts],
    optional: true

  class IndexConstraint
    def matches?(request)
      org = Organization.find_by_login(request.params[:org])
      return false unless org

      team = org.teams.find_by(slug: request.params[:team_slug])
      return false unless team

      team.migration_complete
    end
  end

  layout "team"
  javascript_bundle "manage-membership"

  before_action :login_required
  before_action :this_team_required
  before_action :set_team_context_crumb, only: [:index]
  before_action :admin_on_team_required, except: [:index, :archived_team_posts]
  before_action :sudo_filter, only: [:destroy]
  before_action :sudo_filter, except: %i(
    index
    destroy
    migrate_to_collaborator
    set_role
    suggestions
  )
  before_action :restrict_externally_managed_team, only: [:destroy, :create]

  before_action only: %i(
    destroy
    set_role
    migrate_to_collaborator
  ) do
    T.bind(self, Orgs::TeamMembersController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: team_members_url(this_organization))
  end

  before_action :ensure_can_convert_to_outside_collaborators, only: [:migrate_to_collaborator]

  # todo - remove when cleaning up team_member_rate_limit_fix FF
  include Orgs::Invitations::RateLimiting
  setup_org_invite_rate_limiting only: [:create]

  MEMBER_PAGE_SIZE = 30

  def index
    set_hovercard_subject(this_organization)

    parsed_query = TeamMemberQueryComponents.new(params[:query], graphql: false)

    members = Team::Membership::ScopeBuilder.new(
      team_id: this_team.id,
      viewer: current_user,
      membership: parsed_query.membership,
      role: parsed_query.role,
      query: parsed_query.query,
      max_members_limit: Organization::MEGA_ORG_MEMBER_THRESHOLD
    ).scope.includes(:profile).paginate(page: params[:page], per_page: MEMBER_PAGE_SIZE)

    immediate_member_scope = Team::Membership::ScopeBuilder.new(
      team_id: this_team.id,
      viewer: current_user,
      membership: :immediate,
      max_members_limit: Organization::MEGA_ORG_MEMBER_THRESHOLD
    ).scope

    child_member_scope = Team::Membership::ScopeBuilder.new(
      team_id: this_team.id,
      viewer: current_user,
      membership: :child_team,
      max_members_limit: Organization::MEGA_ORG_MEMBER_THRESHOLD
    ).scope

    options = {
      organization: this_organization,
      team: this_team,
      membership: parsed_query.respond_to?(:membership) ? T::unsafe(parsed_query).membership : nil,
      role: parsed_query.respond_to?(:role) ? T::unsafe(parsed_query).role : nil,
      members: members,
      immediate_members: immediate_member_scope,
      child_members: child_member_scope,
    }

    override_analytics_location "/orgs/<org-login>/teams/<team-name>/members"
    strip_analytics_query_string

    respond_to do |format|
      format.html do
        view = create_view_model(Orgs::TeamMembers::IndexPageView, options)
        if request.xhr?
          render partial: "orgs/team_members/member_table", locals: { view: view }
        else
          # todo - when cleaning up team_member_rate_limit_fix FF, remove the rate_limited field and associated erb logic
          render "orgs/team_members/index", locals: {
            rate_limited: T.must(this_organization).feature_enabled?(:team_member_rate_limit_fix) ? false : org_invite_rate_limited?,
            selected_nav_item: :members,
            view: view,
          }
        end
      end
      format.json do
        team_members_scope = this_team.descendant_or_self_members
        total = team_members_scope.count
        members = team_members_scope.first(20).map(&:display_login).sort_by(&:downcase)
        render json: { total: total, members: members }
      end
    end
  end

  def create
    invitation_options = {
      user: User.find_by_login(params[:member]),
      email: User.valid_email?(params[:member]) ? params[:member] : nil,
      inviter: current_user,
    }

    if invitation_options[:user].blank? && invitation_options[:email].blank?
      add_member_status = Team::AddMemberStatus::BLOCKED
      invitation_options[:user] = User.new login: params[:member]
    elsif invitation_options[:email] && email_verification_required?
      # User must have verified email address to send invites to email addresses
      return render_email_verification_required
    else
      result = begin
        this_team.add_or_invite_member(**invitation_options)
      rescue OrganizationInvitation::NoAvailableSeatsError => e
        GitHub.logger.error({
          exception: e,
          "code.namespace": "Orgs::TeamMembersController",
          "gh.invitation.options": invitation_options,
          "gh.params": params
        })

        Team::AddMemberStatus::NO_SEAT
      end

      if result.is_a?(Team::AddMemberStatus)
        add_member_status = result
      else
        invitation = result
      end
    end

    if result == false
      render_404 and return
    end

    if add_member_status && add_member_status.error?
      member = invitation_options[:user]
      login_or_email = (member && member.display_login) || invitation_options[:email]
      org_or_business = this_team.organization.business.present? ? "enterprise" : "organization"

      case add_member_status
      when Team::AddMemberStatus::BLOCKED
        error = "#{login_or_email} is blocked from joining this organization."
      # NOTE - Team::AddMemberStatus::DUPE cannot happen here because it is a success and not an error
      when Team::AddMemberStatus::NO_SEAT
        error = "You have no remaining seats in your #{org_or_business}. Please purchase at least one additional seat before inviting #{login_or_email} to #{this_team.organization.safe_profile_name}."
      when Team::AddMemberStatus::NO_2FA
        error = "#{login_or_email} needs to enable two-factor authentication."
      when Team::AddMemberStatus::GITHUB_EMPLOYEE_NO_SMS_2FA
        error = "#{login_or_email} must have 2FA configured with an Authenticator app and not SMS/Text message in order to join the github organization as an employee."
      when Team::AddMemberStatus::NO_PERMISSION
        error = "You do not have permission to invite #{login_or_email}."
      when Team::AddMemberStatus::NO_SAML_SSO
        error = "#{login_or_email} needs to satisfy the SAML SSO requirements for this organization."
      when Team::AddMemberStatus::NOT_USER
        error = "#{login_or_email} is not a human user and cannot join any team."
      when Team::AddMemberStatus::PENDING_CYCLE_NO_SEAT
        error = "Your organization has a pending seat downgrade. Please cancel your pending change before inviting #{login_or_email} to #{this_team.organization.safe_profile_name}."
      when Team::AddMemberStatus::TRADE_CONTROLS_RESTRICTED
        error = add_member_status.message
      when Team::AddMemberStatus::ORG_FLAGGED_SPAMMY
        error = add_member_status.message
      when Team::AddMemberStatus::RATE_LIMIT_EXCEEDED
        error = add_member_status.message
      else
        error = "Error adding #{login_or_email} to #{this_team.name}."
      end

      flash[:error] = error
    end
    redirect_to team_members_path(this_team)
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      view = create_view_model(Orgs::TeamMembers::SuggestionsView,
        organization: this_organization,
        team: this_team,
        query: params[:q],
        include_teams: false
      )

      format.html_fragment do
        render partial: "orgs/team_members/suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "orgs/team_members/suggestions", locals: { view: view }
      end
    end
  end

  def destroy
    if params[:member]
      members = []
      member = User.find_by_login(params[:member])
      members << member if member && this_team.member?(member)
    else
      members = this_team.members(actor_ids: params[:team_members_ids].split(",")).to_a
    end

    members.each do |member|
      this_team.remove_member(member)
    end

    if members.length == 1
      flash[:notice] = "You've removed #{T.must(members.first).display_login} from the team."
    else
      flash[:notice] = "You've removed #{members.length} members from the team."
    end

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  def set_role # rubocop:todo GitHub/UseRestfulActions
    members = this_team.members(actor_ids: params[:team_member_ids].split(","))

    total_changed = 0

    members.each do |member|
      # TODO: consider ignoring team_member_ids for members who are already the desired role
      if !this_organization.admins.include?(member)
        case params[:role]
        when "maintainer"
          this_team.promote_maintainer(member)
          total_changed += 1
        when "poster"
          this_team.demote_maintainer(member, with_posting_ability: true)
          total_changed += 1
        when "member"
          this_team.demote_maintainer(member, with_posting_ability: false)
          total_changed += 1
        end
      end
    end

    flash[:notice] = if total_changed > 0
      "#{params[:role] == "maintainer" ? "Promoted" : "Demoted"} #{total_changed} #{"member".pluralize(total_changed)} (Organization owners unaffected)."
    else
      "This action has no effect on Organization owners."
    end

    redirect_to team_members_path(this_team)
  end

  def set_maintainer # rubocop:todo GitHub/UseRestfulActions
    member = this_team.members.find_by_login!(params[:member])

    if params[:maintainer] == "1"
      flash[:notice] = "#{member} is now a team maintainer."
      this_team.promote_maintainer(member)
    else
      flash[:notice] = "#{member} is no longer a team maintainer."
      this_team.demote_maintainer(member)
    end

    redirect_to team_members_path(this_team)
  end

  def migrate_to_collaborator # rubocop:todo GitHub/UseRestfulActions
    members = this_organization.visible_users_for(current_user, actor_ids: params[:member_ids].split(","))
    members.each { |user| this_organization.convert_to_outside_collaborator(user) }

    unless request.xhr?
      flash[:notice] = if members.size == 1
        "Migrated #{members.first.display_login} to outside collaborator."
      else
        "Migrated #{members.size} people to outside collaborators."
      end
    end

    respond_to do |format|
      format.json { head 204 }
      format.html { redirect_to team_members_path(this_team) }
    end
  end

  def archived_team_posts # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_team.post_archive_readable_by?(current_user)

    team_posts = this_team.get_team_posts_scope(current_user)
    replies = DiscussionPostReply.where(discussion_post_id: team_posts.map(&:id))

    GitHub::PrefillAssociations.prefill_associations(team_posts, [:user])
    GitHub::PrefillAssociations.prefill_associations(replies, [:user])

    render json: format_archive_json(team_posts)
  end

  private

  def format_archive_json(team_posts)
    JSON.pretty_generate(
      team_posts.as_json(
        only: [:title, :body, :created_at],
        include: {
          user: { only: [:login] },
          replies: {
            only: [:body, :created_at],
            include: {
              user: { only: [:login] }
            }
          }
        }
      )
    )
  end

  def ensure_can_convert_to_outside_collaborators
    render_404 unless this_organization.allow_conversion_to_outside_collaborator?(actor: current_user)
  end

  def email_verification_required?
    authorization = ContentAuthorizer.authorize(
      current_user, :organization_invitation, :create
    )

    authorization.has_email_verification_error?
  end

  # todo - remove when cleaning up team_member_rate_limit_fix FF
  def org_invite_rate_limited
    org_invite_rate_limit_policy.record_rate_limited(action_name, controller_name)

    render status: 429, json: {
      message_html: render_to_string(
        partial: "orgs/invitations/rate_limited_message",
      ),
    }
  end

  def restrict_externally_managed_team
    return if this_team.locally_managed?
    flash[:error] = "This team is configured for automatic sychronization, manual changes cannot be applied."
    redirect_to team_members_path(this_team)
  end
end
