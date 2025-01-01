# typed: strict
# frozen_string_literal: true

class CodeSecurity::SectionHeadComponent < ApplicationComponent

  sig { params(cant_toggle_due_to_policy: T::Boolean).void }
  def initialize(cant_toggle_due_to_policy:)
    @cant_toggle_due_to_policy = cant_toggle_due_to_policy
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
    CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository: current_repository)
  end

  sig { returns(T::Boolean) }
  def code_security_enabled
    CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: current_repository)
  end
end
