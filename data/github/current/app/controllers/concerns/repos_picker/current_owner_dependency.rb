# typed: strict
# frozen_string_literal: true

module ReposPicker::CurrentOwnerDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  private

  sig { returns(T.nilable(User)) }
  memoize def current_owner
    return unless login = controller.params[:owner]

    User.find_by_login(login)
  end

  sig { returns(T.nilable(Business)) }
  memoize def current_enterprise
    return unless slug = controller.params[:enterprise]

    Business.find_by(slug:)
  end

  sig { returns(T.any(User, Symbol, NilClass)) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless controller.logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    controller.current_user
  end

  sig { returns(T.any(User, Business, Symbol, NilClass)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_owner || current_enterprise
  end

  sig { returns(ApplicationController) }
  def controller
    T.bind(self, ApplicationController)
  end
end
