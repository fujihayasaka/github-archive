# typed: strict
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class RepositoriesController < Orgs::Controller
    include PersonalAccessTokensControllerHelper

    depends_on_clusters ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Permissions,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags

    helper_method :octicon_for

    PAGE_SIZE = 1000

    sig { void }
    def index
      with_conditional_trace do |repositories|
        render partial: "orgs/settings/third_party_access/personal_access_tokens/filters/repositories_content",
          layout: false,
            locals: {
              selected_repository: fetch_from_filter(current_organization, "repository", params[:q]),
              repositories: repositories,
              total_pages: repositories.try(:total_pages) || 1
            }
      end
    end

    private

    sig { params(block: T.proc.params(repositories: ActiveRecord::Relation).void).void }
    def with_conditional_trace(&block)
      trace_controller = "orgs_settings_third_party_access_personal_access_tokens_repositories_controller"
      do_tracing = current_organization.feature_enabled?(:org_pats_repos_trace)
      repositories =
        if do_tracing
          GitHub.tracer.in_span("#{trace_controller}#repositories_paginated_and_sorted", kind: :internal) { repositories_paginated_and_sorted }
        else
          repositories_paginated_and_sorted
        end

      if do_tracing
        GitHub.tracer.in_span("#{trace_controller}#index",
            attributes: {
              "gh.org.id" => current_organization&.id,
              "gh.current_user.id" => current_user&.id
            },
            kind: :internal
        ) do
          yield repositories
        end
      else
        yield repositories
      end
    end

    sig { returns(ActiveRecord::Relation) }
    def repositories_paginated_and_sorted
      current_organization.repositories.select(
        :id, :name, :description, :public, :parent_id, :source_id
      ).paginate(page: 1, per_page: PAGE_SIZE).order(name: :asc)
    end

    sig { returns(T.untyped) }
    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end

    sig { params(repository: Repository).returns(Symbol) }
    def octicon_for(repository)
      if repository.internal?
        :organization
      elsif repository.fork?
        :"repo-forked"
      elsif repository.private?
        :"repo-locked"
      else
        :repo
      end
    end
  end
end
