# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::CustomAgentsSourceOrgSuggestionsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot

  before_action :ai_controls_enabled?
  before_action :ai_controls_read_required

  MAX_SUGGESTIONS = 10

  sig { void }
  def index
    respond_to do |format|
      format.json do
        render json: orgs_for(params[:q])
      end
    end
  end

  private

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { params(query: T.nilable(String)).returns(T::Array[T::Hash[Symbol, String]]) }
  def orgs_for(query)
    if query.present?
      scope = this_business&.organizations.active
      return [] unless scope

      exact_match = scope.where("users.display_login = :query", query: query).first

      scope = scope.where("users.display_login like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      if scope.present? && scope.any?
        scope = scope.order("users.display_login").limit(MAX_SUGGESTIONS)

        matching_orgs = scope.to_a
        matching_orgs = matching_orgs.prepend(exact_match) if exact_match
        matching_orgs = matching_orgs.uniq.compact
      end
    else
      scope = this_business&.organizations.active
      return [] unless scope

      matching_orgs = scope.order("users.display_login").limit(MAX_SUGGESTIONS)
    end

    matching_orgs&.map { |org| simple_organization_payload(org) } || []
  end

  sig { params(org: Organization).returns(T::Hash[Symbol, T.untyped]) }
  def simple_organization_payload(org)
    {
      id: org.id,
      name: org.display_login,
      primaryAvatarUrl: org.primary_avatar_url
    }
  end
end
