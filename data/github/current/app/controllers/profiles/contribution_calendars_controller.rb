# typed: true
# frozen_string_literal: true

module Profiles
  class ContributionCalendarsController < ApplicationController
    include Profiles::ContributionGraphDependency

    before_action :apply_contribution_calendar_cors
    before_action :force_json_for_contribs
    before_action :ensure_user_exists
    # This endpoint is intentionally limited to GitHub.com (dotcom) only.
    # It should not be exposed / callable in multi-tenant enterprise mode because
    # the contribution calendar aggregation semantics, caching scope, and privacy
    # expectations are specific to the dotcom production environment.
    before_action :ensure_dotcom_only

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Repositories,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Iam,
      ApplicationRecord::Profiles,
      only: [:show]

    def show
      # Cache key: user + current date (UTC). Bump key structure manually if format changes.
      date_key = Time.current.utc.to_date.iso8601
      cache_key = cache_key_for(user_id: this_user.id, date_key: date_key)

      payload = GitHub.cache.fetch(cache_key) do
        calendar = Contribution::Calendar.new(collector: non_graphql_calendar_collector)
        Profiles::ContributionCalendarSerializer.new(calendar: calendar).as_json
      end

      render json: payload
    end

    # Handle CORS preflight (OPTIONS) requests.
    def options # rubocop:todo GitHub/UseRestfulActions
      # CORS headers already set by before_action
      head :no_content
    end

    private

    # Apply permissive CORS headers (mirroring API middleware) so that this
    # dotcom-only JSON endpoint can be safely consumed cross-origin (e.g. by
    # simple fetch() requests). We intentionally reuse the constants from
    # Api::Middleware::Cors so that is aligned to our API behavior.
    def apply_contribution_calendar_cors
      allow_origin = Api::Middleware::Cors::DEFAULT_ORIGIN
      headers[Api::Middleware::Cors::ALLOW_ORIGIN] ||= allow_origin

      if request.options?
        # Preflight: set headers.
        Api::Middleware::Cors::PREFLIGHT_CORS.each do |k, v|
          headers[k] ||= v
        end
      else
        # Regular request: expose headers.
        Api::Middleware::Cors::CORS.each do |k, v|
          headers[k] ||= v
        end
      end
    rescue NameError => e
      Rails.logger.warn("CORS constants unavailable for contribution calendar: #{e.class}: #{e.message}")
    end

    # Delegate to UserContributionsHelper methods via helpers proxy to avoid duplicating logic.
    # UserContributionsHelper is in app/helpers, which is auto-included in views but not controllers,
    # so we access it through the helpers module to comply with monolith-fitness guidelines.
    def this_user
      helpers.this_user
    end

    def scoped_organization
      helpers.scoped_organization
    end

    def parse_date_from(date_str)
      helpers.parse_date_from(date_str)
    end

    def ensure_user_exists
      render_404 unless this_user && this_user.user?
    end

    # 404 in any non-dotcom multi-tenant environment.
    # We explicitly allow execution only when NOT in multi-tenant enterprise mode.
    def ensure_dotcom_only
      if GitHub.respond_to?(:multi_tenant_enterprise?) && GitHub.multi_tenant_enterprise?
        render_404
      end
    end

    # Force the request format to JSON for legacy `.contribs` extension.
    def force_json_for_contribs
      if request.path.ends_with?(".contribs") && request.format.symbol != :json
        request.format = :json
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to coerce format for .contribs: #{e.class}: #{e.message}")
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def resource_for_conditional_access
      :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    end

    def cache_key_for(user_id:, date_key:)
      version = Profiles::ContributionCalendarSerializer::SCHEMA_VERSION
      "profiles:contrib_calendar_json:#{version}:#{user_id}:#{date_key}"
    end
  end
end
