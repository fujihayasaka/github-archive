# typed: strict
# frozen_string_literal: true

module ReposPicker::CurrentOrganizationDependency
  include GitHub::Memoizer

  private

  sig { returns(T.nilable(Organization)) }
  memoize def current_organization
    return unless T.unsafe(self).params[:org]

    Organization.find_by_login(T.unsafe(self).params[:org])
  end

  sig { returns(T.nilable(T.any(User, Symbol))) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless T.unsafe(self).logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    T.unsafe(self).current_user
  end

  sig { returns(T.nilable(T.any(Organization, Symbol))) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_organization
  end
end
