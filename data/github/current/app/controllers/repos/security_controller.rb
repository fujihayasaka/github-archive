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
    ApplicationRecord::Iam,
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
          rescue => exception
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
    # The sidebar renders Dependabot and secret-scanning as separate sub-items, so we need to track the sub-counts
    # here and sum them after the loop so the navbar cache values get updated properly.

    cache_updates = {}
    dependabot_split_counts = {}
    token_scanning_split_counts = {}

    response = ActiveRecord::Base.connected_to(role: :reading) do
      view = Navigation::Repository::SecurityView.new(current_user: current_user, current_repository: current_repository)

      params.require(:items).permit!.to_h.transform_values do |item|
        count = case item[:type]
        when "advisories"
          view.security_advisories_count if view.show_advisories?
        when "dependabot-alerts"
          view.security_network_alerts_count if view.show_dependabot_alerts?
        when "dependabot-malware-alerts"
          view.security_malware_alerts_count if view.show_dependabot_alerts?
        when "dependabot-vulnerability-alerts"
          view.security_vulnerability_alerts_count if view.show_dependabot_alerts?
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

        # capture counts that map to the navigation tab cache so we can refresh the cache without doing any extra database queries
        if count
          case item[:type]
          when "advisories"                          then cache_updates[:advisories_count] = count
          when "dependabot-alerts"                   then cache_updates[:dependabot_count] = count
          when "dependabot-malware-alerts"           then dependabot_split_counts[:malware] = count
          when "dependabot-vulnerability-alerts"     then dependabot_split_counts[:vulnerability] = count
          when "code-scanning-alerts"                then cache_updates[:code_scanning_count] = count
          when "secret-scanning-alerts"              then cache_updates[:token_scanning_count] = count
          when "secret-scanning-alerts-default"      then token_scanning_split_counts[:default] = count
          when "secret-scanning-alerts-generic"      then token_scanning_split_counts[:generic] = count
          end
        end

        render_to_string Primer::Beta::Counter.new(count: count || 0, limit: 5_000, hide_if_zero: true), layout: false
      end
    end

    if FeatureFlag.vexi.enabled?(:global_navigation_refresh_security_cache, current_repository, default: false)
      # Combine the Dependabot split counts into the dependabot navbar cache slot
      if dependabot_split_counts.key?(:malware) && dependabot_split_counts.key?(:vulnerability)
        cache_updates[:dependabot_count] = dependabot_split_counts[:malware] + dependabot_split_counts[:vulnerability]
      end

      # Also combine the token scanning split counts for the navbar cache
      if token_scanning_split_counts.key?(:default) && token_scanning_split_counts.key?(:generic)
        cache_updates[:token_scanning_count] = token_scanning_split_counts[:default] + token_scanning_split_counts[:generic]
      end

      if cache_updates.any?
        # update the cached navigation tab count using the values we just computed
        # so the navigation tab doesn't show a stale count
        with_database_error_fallback do
          SecurityProducts.domain.update_security_alert_count_cache_for_repo(
            current_repository,
            current_user,
            **cache_updates,
          )
        end
      end
    end

    respond_to { |format| format.json { render json: response } }
  end

  def overview # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Repositories::SecurityOverviewView,
      repository: current_repository,
      current_user: current_user,
      permissions: permissions,
    )
    render "repos/security/overview", locals: { view: view }
  end

  def policy # rubocop:todo GitHub/UseRestfulActions
    render "repos/security/policy"
  end

  private

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def permissions
    helpers.view_permissions
  end
end
