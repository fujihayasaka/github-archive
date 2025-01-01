# typed: true
# frozen_string_literal: true

class Repos::SecurityController < AbstractRepositoryController
  preload_features [:disable_code_scanning]

  before_action :require_xhr, only: :counts

  map_to_service :advisory_database, only: [:policy] # rubocop:todo GitHub/MapToService

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:counts]

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:overall_count]

  depends_on_clusters \
    ApplicationRecord::Notify,
    only: [:overall_count],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:overview]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:overview],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:policy]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:policy],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:overview, :policy], optional: true

  def overall_count # rubocop:todo GitHub/UseRestfulActions
    view = Navigation::Repository::SecurityView.new(current_user: current_user, current_repository: current_repository)

    respond_to do |format|
      format.html_fragment do
        # If we are only allowed to see security advisories, then we can set a
        # fairly aggresive cache as they do not change very frequently
        expires_in 4.hours if view.show_advisory_count_only?

        # Catch and report any errors, but allow a fallback to 0.
        # This call is async to avoid breaking any request, so non-critical.
        fallback = 0
        security_count = \
          with_database_error_fallback(fallback:) do
            view.security_count
          rescue => exception # rubocop:disable Lint/RescueException
            Failbot.report(exception, {
              "gh.repo.id": current_repository.id,
              "gh.actor.login": current_user.display_login,
            })
            fallback
          end

        render partial: "repos/security/tab_count", locals: {
          security_count:
        }, formats: :html
      end

      format.all do
        render_404
      end
    end
  end

  def counts # rubocop:todo GitHub/UseRestfulActions
    response = ActiveRecord::Base.connected_to(role: :reading) do
      view = Navigation::Repository::SecurityView.new(current_user: current_user, current_repository: current_repository)

      params.require(:items).permit!.to_h.transform_values do |item|
        count = case item[:type]
        when "advisories"
          view.security_advisories_count if view.show_advisories?
        when "dependabot-alerts"
          view.security_network_alerts_count if view.show_dependabot_alerts?
        when "code-scanning-alerts"
          view.security_code_scanning_count if view.show_code_scanning?
        when "secret-scanning-alerts"
          view.security_token_scanning_count if view.show_token_scanning_results?
        when "secret-scanning-alerts-generic"
          view.security_token_scanning_count_generic if view.show_token_scanning_results?
        when "secret-scanning-alerts-default"
          view.security_token_scanning_count_default if view.show_token_scanning_results?
        when "bypass-requests"
          view.security_bypass_requests_count if view.show_bypass_requests?
        end

        render_to_string Primer::Beta::Counter.new(count: count || 0, limit: 5_000, hide_if_zero: true), layout: false
      end
    end

    respond_to { |format| format.json { render json: response } }
  end

  def overview # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Repositories::SecurityOverviewView,
      repository: current_repository,
      current_user: current_user,
    )
    render "repos/security/overview", locals: { view: view }
  end

  def policy # rubocop:todo GitHub/UseRestfulActions
    render "repos/security/policy"
  end
end
