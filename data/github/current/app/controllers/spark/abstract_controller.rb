# typed: true
# frozen_string_literal: true

class Spark::AbstractController < ApplicationController
  abstract!

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :require_logged_in_user
  before_action :require_feature_enabled

  private

  # NOTE: we have a `login_required` method available to all controllers
  # that redirects to /login if the user is not logged in but
  # we want to render a 404 to avoid leaking any info about the feature
  def require_logged_in_user
    render_404 unless logged_in?
  end

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    current_user&.feature_enabled?(:spark_dashboard)
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  memoize def sso_organizations
    orgs = Organization.where(id: saml_for_user.protected_organization_ids)

    orgs.map do |org|
      {
        id: org.id.to_s,
        login: org.display_login,
        avatarUrl: org.primary_avatar_url
      }
    end
  end

  sig { params(cap_filter: ConditionalAccess::Web::Filter, user: User).returns(T::Array[Organization]) }
  def saml_authorized_organizations(cap_filter, user)
    result_set = cap_filter.authorized(user.organizations, only: :saml)
    result_set.results.map { |r| r.resource }
  end
end
