# typed: true
# frozen_string_literal: true

class Copilot::NextEditSuggestionsWaitlistSignupController < ApplicationController
  before_action :login_required, except: [:new]
  before_action :dotcom_required
  before_action :ensure_not_proxima
  before_action :ensure_not_emu
  before_action :require_feature_enabled

  stylesheet_bundle :signup_copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:new, :join]

  FEATURE_SLUG = :copilot_next_edit_suggestions

  def new
    return redirect_to copilot_next_edit_suggestions_waitlist_signup_join_path if logged_in?

    context_region_title "Copilot Next Edit Suggestions (NES) Waitlist"

    render "copilot/next_edit_suggestions_waitlist_signup/new"
  end

  def join # rubocop:todo GitHub/UseRestfulActions
    context_region_title "Copilot Next Edit Suggestions (NES) Waitlist"

    if current_user_on_waitlist?
      return render "copilot/next_edit_suggestions_waitlist_signup/success", locals: {
        display_login: current_user.display_login,
      }
    end

    render "copilot/next_edit_suggestions_waitlist_signup/join", locals: {
      has_cfi_access: has_cfi_access?,
      has_cfb_access: has_cfb_access?,
      preview_terms: beta.preview_terms,
    }
  end

  def create
    context_region_title "Copilot Next Edit Suggestions (NES) Waitlist"

    # clear flash if it's been set by a previous request and not dismissed by the user
    flash[:error] = nil
    flash[:notice] = nil

    unless flash[:error] || flash[:notice]
      if create_early_access_membership
        return render "copilot/next_edit_suggestions_waitlist_signup/success", locals: {
          display_login: current_user.display_login,
        }
      else
        flash[:error] = "There was a problem adding you to the waitlist."
      end
    end

    render "copilot/next_edit_suggestions_waitlist_signup/join", locals: {
      has_cfi_access: has_cfi_access?,
      has_cfb_access: has_cfb_access?,
      preview_terms: beta.preview_terms,
    }
  end

  private

  def require_feature_enabled
    return if GitHub.flipper[:copilot_nes_signup].enabled? # this means it's globally shipped
    return if current_user&.feature_enabled?(:copilot_nes_signup) # this means it's enabled for the user

    render_404
  end

  def current_user_can_sign_up?
    return false unless logged_in?
    return false if copilot_authorizer.access_type == :NOT_EVALUATED

    true
  end

  memoize def has_cfi_access?
    current_user_can_sign_up? && current_copilot_user&.has_cfi_access?
  end

  memoize def has_cfb_access?
    current_user_can_sign_up? && current_copilot_user&.has_cfb_access?
  end

  def current_user_on_waitlist?
    return false unless logged_in?

    EarlyAccessMembership.on_waitlist?(FEATURE_SLUG, current_user)
  end

  def create_early_access_membership
    return false unless has_cfi_access?
    return true if current_user_on_waitlist?

    membership = EarlyAccessMembership.new(
      member_id: current_user.id,
      actor_id: current_user.id,
      feature_slug: beta.feature_slug,
      survey: survey,
    )

    membership.save_with_survey_answers(terms_survey_answers)
  end

  # Since we tell users that signing up for the waitlist requires agreeing to our terms,
  # we find and submit the correct survey response ourselves.
  memoize def terms_survey_answers
    question = survey.questions.find_by_short_text("github_next_prerelease_terms")
    choice = question.choices.find_by_short_text("agree_github_next_prerelease_terms")

    [{
      question_id: question.id,
      choice_id: choice.id
    }]
  end

  memoize def copilot_authorizer
    current_copilot_user&.copilot_authorizer_object_no_snippy
  end

  def ensure_not_emu
    render_404 if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed?
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def ensure_not_proxima
    render_404 if GitHub.multi_tenant_enterprise?
  end

  memoize def beta
    ::Copilot::NextEditSuggestionsBeta.new
  end

  memoize def survey
    Copilot::NextEditSuggestionsWaitlistSurvey.find_survey
  end
end
