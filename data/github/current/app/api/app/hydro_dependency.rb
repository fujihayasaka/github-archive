# typed: true
# frozen_string_literal: true

#
# This module is used to manage the request details associated with the API request, which are published to Hydro
# after the request is completed (either successfully or with an error).
#
module Api::App::HydroDependency
  extend T::Helpers

  requires_ancestor { Api::App }

  def finalize_hydro_context
    GitHub.tracer.in_span("api.app-after", kind: :internal, attributes: {
      "code.namespace" => "finalize_hydro_context"
    }) do |_span|
      if hydro_context[:enabled]
        # login used only in hydro therefore safe to use here.
        hydro_context.merge!({
          request_category: request_category,
          controller: self.class.name,
          api_route: route_pattern,
          auth_type: Hydro::EntitySerializer.auth_type(GitHub.context[:auth]) || :AUTH_UNKNOWN,
          current_user: current_user&.bot? ? current_user.display_login : current_user&.login, # rubocop:disable GitHub/DoNotAllowLogin
          current_user_id: current_user&.id,
          analytics_tracking_id: current_user&.analytics_tracking_id,
          oauth_application_id: GitHub.context[:oauth_application_id],
          oauth_access_id: GitHub.context[:oauth_access_id],
          oauth_scopes: GitHub.context[:oauth_scopes],
          integration_id: GitHub.context[:integration_id],
          integration_installation_id: GitHub.context[:installation_id],
          user_programmatic_access_id: GitHub.context[:user_programmatic_access_id],
          api_version: medias.to_api_semantic_version,
          rate_limit_amount: increment_rate_limit_amount,
          server: GitHub.local_host_name,
          api_request_owner_id: request_owner&.id,
          actor_name: GitHub.context[:actor_name],
        })

        if @selected_api_version && !@selected_api_version.skipped?
          hydro_context.merge!({
            requested_api_version: @selected_api_version.requested_version,
            selected_api_version: @selected_api_version.version,
          })
        end

        # This is split out here, as the GraphQL code could have set this already in the context.
        # The processing of rate limits from GraphQL is handled in `app/api/graph_ql.rb` and
        # `redis_rate_limiter.rb` so for those requests, @rate is nil.
        if @rate
          @rate.update_hydro(hydro_context)
        end

        if current_repo_loaded?
          # nwo used only in hydro thefore safe to use nwo here.
          hydro_context.merge!({
            current_repo: current_repo.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner
            current_repo_id: current_repo.id,
            current_repo_visibility: (current_repo.private? ? :PRIVATE : :PUBLIC),
          })
        end

        if org = current_resource_org_or_biz_owner
          if current_user
            ActiveRecord::Base.connected_to(role: :reading) do
              hydro_context.merge!({
                current_user_is_org_member: !current_user.organizations.find_by(id: org.id).nil?,
                pat_has_sso_access: current_user.oauth_access && !!current_user.oauth_access.credential_authorizations.find_by(organization_id: org.id)
              })
            end
          end

          hydro_context.merge!({
            current_org: org.name,
            current_org_id: org.id,
            current_org_is_org: org.organization?,
          })

        end

      end
    end
  end

  def disable_hydro_request_logging
    hydro_context[:enabled] = false
  end

  def hydro_context
    request.env[GitHub::HydroMiddleware::CONTEXT] ||= {}
  end

  def populate_context_with_controller_action(action_name)
    hydro_context.merge!({
      controller_action: action_name,
    })
  end
end
