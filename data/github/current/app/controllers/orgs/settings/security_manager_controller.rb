# typed: strict
# frozen_string_literal: true

class Orgs::Settings::SecurityManagerController < Orgs::Controller
  extend T::Sig

  # Authorization
  before_action :organization_admin_required

  around_action :track_and_report_mysql_executions
  around_action :set_log_context
  before_action :set_failbot_context

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:suggestions],
    optional: true

  include GitHub::RateLimitedRequest
  rate_limit_requests(
    only: [:add, :remove],
    max: 100,
    ttl: 1.hour,
    key: :add_remove_rate_limit_key,
  )

  sig { void }
  def suggestions # rubocop:todo GitHub/UseRestfulActions
    suggestions = []

    query = AutocompleteQuery.new(
      current_user,
      params[:q],
      organization: current_organization,
      teams_only: true
    )

    suggestions = filter_out_security_managers(query.suggestions) if params && params[:q]

    respond_to do |format|
      # Tests don't use html_fragment (which we use for autocomplete), so to test this, we also need an html option.
      format.html_fragment do
        render(Organizations::Settings::SecurityManagerSuggestionsComponent.new(suggestions: suggestions, organization: current_organization), layout: false, formats: :html)
      end
      format.html do
        render(Organizations::Settings::SecurityManagerSuggestionsComponent.new(suggestions: suggestions, organization: current_organization), layout: false)
      end
    end
  end

  sig { void }
  def remove # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless team

    begin
      SecurityProduct::SecurityManagerRole.revoke! team
    rescue ActiveRecord::RecordInvalid, Permissions::Granters::RoleGranter::GrantFailure, ArgumentError => e
      Failbot.report(e)

      return redirect_to(
        settings_org_security_analysis_path,
        flash: { error: "There was an error removing the team. Please try again." }
      )
    end

    redirect_to(
      settings_org_security_analysis_path,
      flash: { notice: "Security manager permissions removed from team." },
    )
  end

  sig { void }
  def add # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless team

    begin
      SecurityProduct::SecurityManagerRole.grant! team
    rescue ActiveRecord::RecordInvalid, Permissions::Granters::RoleGranter::GrantFailure => e
      Failbot.report(e)

      return redirect_to(
        settings_org_security_analysis_path,
        flash: { error: "There was an error granting security manager permissions to this team." },
      )
    end

    redirect_to(
      settings_org_security_analysis_path(tip: get_onboarding_tip),
      flash: { notice: "Security manager permissions added to team." }
    )
  end

  private

  sig { params(suggestions: T::Array[Team]).returns(T::Array[Team]) }
  def filter_out_security_managers(suggestions)
    security_managers = SecurityProduct::SecurityManagers.new(current_organization).teams
    suggestions - security_managers
  end

  sig { void }
  def render_form_fragment
    render Organizations::Settings::SecurityManagerTeamsComponent.new(
      actor: current_user,
      organization: current_organization,
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def logging_context
    {
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.org.id": current_organization.id,
      "gh.org.login": current_organization.display_login,
      "gh.team.id": team_id,
      "gh.team.slug": team&.slug,
    }
  end

  sig { params(block: T.proc.void).void }
  def set_log_context(&block)
    GitHub.logger.with_named_tags(logging_context) { yield }
  end

  sig { void }
  def set_failbot_context
    Failbot.push({ app: "github-security-center" }.merge(logging_context))
  end

  sig { returns(String) }
  def add_remove_rate_limit_key
    "security_managers:#{current_organization.id}"
  end

  sig { returns(T.nilable(Integer)) }
  memoize def team_id
    team_id = params[:team_id].to_i
  end

  sig { returns(T.nilable(Team)) }
  memoize def team
    return unless team_id
    Team.find_by(id: team_id, organization_id: current_organization.id)
  end

  sig { returns(T.nilable(String)) }
  def get_onboarding_tip
    referrer = Addressable::URI.parse(request.referrer)
    return nil unless referrer && referrer.domain == request.domain
    return nil unless referrer.query_values
    referrer.query_values["tip"]
  end
end
