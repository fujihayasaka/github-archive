# typed: strict
# frozen_string_literal: true

class PersonalAccessTokens::ResourceOwnersController < ApplicationController
  include PersonalAccessTokens::SharedControllerMethods

  before_action :login_required
  before_action :require_programmatic_access_tokens_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  LIMIT = 50

  sig { void }
  def index
    actors = collect_pat_resource_owners(query: params[:q], limit: LIMIT)

    respond_to do |format|
      format.html_fragment do
        render partial: "personal_access_tokens/resource_owner_items", formats: :html, locals: {
          actors: actors,
          current_target: current_target,
          current_access: current_access,
          menu_id: params[:menu_id],
        }
      end
      format.html do
        render partial: "personal_access_tokens/resource_owner_items", locals: {
          actors: actors,
          current_target: current_target,
          current_access: current_access,
          menu_id: params[:menu_id],
        }
      end
    end
  end

  private

  # Collects resource owners (current_user and eligible organizations) for PAT creation.
  sig { params(query: T.nilable(T.any(String, T::Array[String])), limit: Integer).returns(T::Array[T.any(User, Organization)]) }
  def collect_pat_resource_owners(query:, limit:)
    actors = T.let([], T::Array[T.any(User, Organization)])
    sanitized_query = query.present? ? "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s)}%" : nil

    if sanitized_query.nil? || current_user.display_login.downcase.include?(query.to_s.downcase)
      actors << current_user
    end

    orgs_query = current_user.organizations
      .preload(business_membership: :business)

    if sanitized_query
      orgs_query = orgs_query.where(business_id: current_user.business_id).where("display_login LIKE ?", sanitized_query)
    end

    orgs = orgs_query.limit(limit).to_a
    Configurable.preload_configuration([current_user, orgs].flatten)

    orgs = orgs
      .select { |org| org.patsv2_enabled? && org.personal_access_tokens_allowed? }
      .take(limit)

    actors.concat(orgs)
    actors
  end
end
