# typed: true
# frozen_string_literal: true

# Public: Identifies whether a particular HTTP request satisfies the policy for
# for accessing a particular repository.
class OauthApplicationPolicy::HttpRequest < RepositoryPolicy
  attr_reader :request
  attr_reader :user

  # Public: Initialize a OauthApplicationPolicy::HttpRequest.
  #
  # repository - A Repository.
  # request    - A Rack::Request.
  # user       - A User.
  def initialize(repository:, user:, request:)
    @repository = repository
    @request = request
    @user = user
  end

  def satisfied?
    return true unless requestor_governed_by_oauth_application_policy?

    return true if repository.nil?
    return true if repository.public? && (request.try(:head?) || request.try(:get?))

    OauthApplicationPolicy::Application.new(repository, user.oauth_application).satisfied?
  end

  private

  def requestor_governed_by_oauth_application_policy?
    user && user.using_oauth_application? && GitHub.oauth_application_policies_enabled?
  end
end
