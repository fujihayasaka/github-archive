# typed: true
# frozen_string_literal: true

# Public: Identifies whether a particular OAuth app satisfies the policy for
# apps that are allowed to access a particular repository.
class OauthApplicationPolicy::Application < RepositoryPolicy
  attr_reader :app

  # Public: Initialize a OauthApplicationPolicy::Application.
  #
  # repository - A Repository.
  # app        - An OauthApplication.
  def initialize(repository, app)
    @repository = repository
    @app = app
  end

  def satisfied?
    return true if app.oap_exempt?

    if policymaker.nil?
      return false
    end

    consider_owner_and_network_owner_approval = repository.private? &&
      repository.owner.present? &&
      repository.owner.organization? && repository.network_owner.organization? &&
      repository.owner.restrict_oauth_applications? &&
      repository.network_owner.restrict_oauth_applications?

    if consider_owner_and_network_owner_approval
      repository.owner.allows_oauth_application?(app) &&
        repository.network_owner.allows_oauth_application?(app)
    else
      return true unless policymaker.restricts_oauth_applications?

      policymaker.allows_oauth_application?(app)
    end
  end
end
