# typed: strict
# frozen_string_literal: true

module PersonalAccessTokens::SharedControllerMethods
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { void }
  def require_programmatic_access_tokens_enabled
    render_404 unless current_user.patsv2_enabled?
  end

  sig { returns(T.nilable(ProgrammaticAccess)) }
  memoize def current_access
    return unless params[:access_id]
    ProgrammaticAccess.for(current_user).find_by(id: params[:access_id])
  end

  sig { returns(T.any(User, Organization)) }
  memoize def current_target
    if params[:target_name].present? && params[:target_name] != current_user.display_login
      current_user.organizations.find_by(login: params[:target_name]) || current_user
    else
      current_user
    end
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_target.target_for_conditional_access
  end
end
