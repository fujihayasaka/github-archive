# typed: true
# frozen_string_literal: true

module CommandPaletteHelper
  class DetermineScopeError < StandardError
    def initialize(error)
      super
      set_backtrace(error.backtrace)
    end
  end

  extend T::Helpers

  include Kernel

  requires_ancestor { ActionView::Base }

  abstract!

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  sig { abstract.returns(User) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  SUPPORTED_SCOPE_CLASS_NAMES = %w[
    User
    Organization
    Repository
    Issue
    Discussion
    PullRequest
    MemexProject
  ]

  def command_palette_enabled?
    return false unless logged_in?
    current_user.command_palette_enabled?
  end

  def command_palette_scope
    return unless response.ok?
    return if T.unsafe(self).params[:clear_command_scope].present?
    return @command_palette_scope if defined?(@command_palette_scope)

    @command_palette_scope = determine_scope
  end

  def get_owner_scope
    return T.unsafe(self).this_organization if respond_to?(:this_organization) && !T.unsafe(self).this_organization.nil?
    return T.unsafe(self).current_organization if respond_to?(:current_organization) && !T.unsafe(self).current_organization.nil?
    return T.unsafe(self).this_user if respond_to?(:this_user)
  end

  def determine_scope
    scope = T.unsafe(self).page_breadcrumb_object if SUPPORTED_SCOPE_CLASS_NAMES.include?(T.unsafe(self).page_breadcrumb_object.class.name)
    scope ||= current_repository || get_owner_scope

    if scope&.persisted?
      scope
    else
      nil
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    Failbot.report(DetermineScopeError.new(e))
    GitHub.dogstats.increment("command_palette.determine_scope.error")
    nil
  end
end
