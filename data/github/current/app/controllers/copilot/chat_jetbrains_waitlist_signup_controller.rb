# typed: true
# frozen_string_literal: true

class Copilot::ChatJetbrainsWaitlistSignupController < ApplicationController
  before_action :login_required, except: [:new]
  before_action :dotcom_required
  before_action :ensure_not_emu

  stylesheet_bundle :signup_copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:new, :join]

  def new
    return redirect_to copilot_chat_jetbrains_waitlist_signup_join_path if logged_in?

    context_region_title "GitHub Copilot Chat in JetBrains IDEs waitlist"

    render "copilot/chat_jetbrains_waitlist_signup/new"
  end

  def join # rubocop:todo GitHub/UseRestfulActions
    context_region_title "GitHub Copilot Chat in JetBrains IDEs waitlist"

    if current_user_on_waitlist?
      return render "copilot/chat_jetbrains_waitlist_signup/success"
    end

    render "copilot/chat_jetbrains_waitlist_signup/join", locals: {
      has_cfi_access: has_cfi_access?,
      has_cfb_access: has_cfb_access?,
      preview_terms: beta.preview_terms,
    }
  end

  def create
    context_region_title "GitHub Copilot Chat in JetBrains IDEs waitlist"

    if create_early_access_membership
      render "copilot/chat_jetbrains_waitlist_signup/success"
    else
      flash[:error] = "There was a problem adding you to the waitlist."

      render "copilot/chat_jetbrains_waitlist_signup/join", locals: {
        has_cfi_access: has_cfi_access?,
        has_cfb_access: has_cfb_access?,
        preview_terms: beta.preview_terms,
      }
    end
  end

  private

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

    EarlyAccessMembership.on_waitlist?(beta.feature_slug, current_user)
  end

  def create_early_access_membership
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
    question = survey.questions.find_by_short_text("copilot_preview_specific_terms")
    choice = question.choices.find_by_short_text("agree_copilot_preview_specific_terms")

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

  memoize def beta
    ::Copilot::ChatJetbrainsBeta.new
  end

  memoize def survey
    Copilot::ChatJetbrainsBetaWaitlistSurvey.find_survey
  end
end
