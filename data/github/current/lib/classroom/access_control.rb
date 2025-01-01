# typed: true
# frozen_string_literal: true
class Classroom::AccessControl < Platform::Authorization::Permission
  attr_reader :env

  def initialize(context)
    @token = context.fetch(:token)
    context[:origin] = Platform::ORIGIN_API
    context[:viewer] = user
    @env = {}
    super
  end

  def authentication
    @authentication ||= GitHub::Authentication::Attempt.new(
      allow_integrations:                 false,
      allow_user_via_granular_actor:      true,
      from:                               :classroom,
      token:                              token,
      ip:                                 "127.0.0.1",
      password_auth_blocked:              true
    ).result
  end

  def user
    @current_user ||= authentication.user
  end

  def repository_accessible?(repository)
    # Classroom is not supported on GHES
    return false if GitHub.single_business_environment?

    current_org = if repository.owner.is_a?(Organization)
      repository.owner
    end

    access_allowed?(:get_contents,
      resource: repository,
      current_repo: repository,
      current_org: current_org,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      raise_on_error: false,
    )
  end

  def repository_writable?(repository)
    # Classroom is not supported on GHES
    return false if GitHub.single_business_environment?

    current_org = if repository.owner.is_a?(Organization)
      repository.owner
    end

    access_allowed?(:create_commit,
      resource: repository,
      current_repo: repository,
      current_org: current_org,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      raise_on_error: false,
    )
  end

  private

  attr_reader :token
end
