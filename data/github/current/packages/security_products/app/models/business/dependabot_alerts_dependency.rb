# typed: true
# frozen_string_literal: true

module Business::DependabotAlertsDependency
  extend T::Sig

  NEW_REPOS_ENABLED_KEY = "dependabot_alerts.new_repos_enable"

  sig { params(actor: User).returns(T::Boolean) }
  def enable_security_alerts_for_new_repos(actor:)
    T.bind(self, Business)
    config.enable(NEW_REPOS_ENABLED_KEY, actor)
  end

  sig { params(actor: User).returns(T::Boolean) }
  def disable_security_alerts_for_new_repos(actor:)
    T.bind(self, Business)
    config.delete(NEW_REPOS_ENABLED_KEY, actor)
  end

  sig { returns(T::Boolean) }
  def security_alerts_enabled_for_new_repos?
    T.bind(self, Business)
    config.enabled?(NEW_REPOS_ENABLED_KEY)
  end
end
