# typed: true
# frozen_string_literal: true

class FilterProviders::OrganizationsController < FilterProvidersController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations

  def index
    orgs = find_user_organizations.map { |org| format_response(org) }
    respond_payload({ organizations: orgs })
  end

  def show
    if org_from_query
      respond_payload(format_response(org_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  def find_user_organizations
    scope = current_user.organizations
    scope = scope.where("login LIKE ?", like_query_value) if query_value.present?
    scope.by_login.limit(maximum_result_limit)
  end

  memoize def org_from_query
    return nil unless query_value.present?
    current_user.organizations.find_by(login: query_value)
  end

  def format_response(org)
    {
      name: org.safe_profile_name,
      login: org.display_login,
      avatarUrl: org.primary_avatar_url(60),
    }
  end

  def resource_for_conditional_access
    return self unless action_name == "show"
    return org_from_query if org_from_query.present?
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    org_from_query || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
