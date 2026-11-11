# typed: strict
# frozen_string_literal: true

class CodeSecurity::SectionHeadComponent < ApplicationComponent

  sig do
    params(
      repository: Repository,
      button_disabled: T::Boolean,
      button_disabled_message: T.nilable(String)
    ).void
  end
  def initialize(repository:, button_disabled:, button_disabled_message: nil)
    @repository = repository
    @button_disabled = button_disabled
    @button_disabled_message = button_disabled_message
  end

  sig { returns(String) }
  def billing_text
    if GitHub.enterprise?
      "Code Security features are billed for per 90-day active committer for all repositories"
    else
      "Code Security features are free for public repositories and billed for per 90-day active committer for private and internal repositories."
    end
  end

  sig { returns(T::Boolean) }
  def show_button?
    CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository: @repository)
  end

  sig { returns(T::Boolean) }
  def code_security_enabled
    CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: @repository)
  end

  sig { returns(T::Boolean) }
  def enablement_blocked?
    ::CodeSecurity::Features::AdvancedSecurityHelper.code_security_metered_usage_locked?(repository: @repository)
  end
end
