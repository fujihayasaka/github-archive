# typed: strict
# frozen_string_literal: true

class PersonalAccessTokens::CheckNameController < ApplicationController
  before_action :login_required

  sig { void }
  def index
    return render_404 unless current_user.patsv2_enabled?

    token = UserProgrammaticAccess.new(owner: current_user, name: params[:value])
    token.valid?

    respond_to do |format|
      format.html_fragment do
        if token.errors[:name].any?
          return render partial: "personal_access_tokens/validation/check_name_error",
                locals: { token: token },
                status: :unprocessable_entity,
                formats: :html
        else
          return render partial: "personal_access_tokens/validation/check_name",
                locals: { token: token },
                formats: :html
        end
      end
    end
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
