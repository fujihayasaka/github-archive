# typed: strict
# frozen_string_literal: true

module CopilotSummariesHelper
  include GitHub::Memoizer
  extend T::Helpers

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { returns T.nilable(T::Boolean) }
  memoize def staff_viewer?
    current_user&.site_admin? || current_user&.employee?
  end
end
