# typed: true
# frozen_string_literal: true

class OauthApplicationPolicy::Hook
  attr_reader :hook, :hook_event
  delegate :target_repository, :target_organization, to: :hook_event

  def initialize(hook, hook_event)
    @hook = hook
    @hook_event = hook_event
  end

  def app
    hook.oauth_application
  end

  def repo_event?
    target_repository.present?
  end

  def policymaker
    if repo_event?
      target_repository.policymaker
    else
      target_organization
    end
  end

  def violated?
    !satisfied?
  end

  def satisfied?
    return true unless app

    if repo_event?
      target_repository.public? || OauthApplicationPolicy::Application.new(target_repository, app).satisfied?
    else
      return false unless target_organization
      target_organization.allows_oauth_application?(app)
    end
  end
end
