# typed: true
# frozen_string_literal: true

class Copilot::FineTuningWaitlistSignupController < ApplicationController
  before_action :login_required, except: [:new]
  before_action :dotcom_required
  before_action :ensure_not_proxima

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

  def new
    return redirect_to copilot_fine_tuning_waitlist_signup_join_path if logged_in?

    redirect_to "/features/preview/copilot-customization"
  end

  def join # rubocop:todo GitHub/UseRestfulActions
    context_region_title "GitHub Copilot fine-tuning waitlist"

    render "copilot/fine_tuning_waitlist_signup/join", locals: {
      preview_terms: beta.preview_terms,
      organizations: current_user.organizations,
    }
  end

  def create
    context_region_title "GitHub Copilot fine-tuning waitlist"

    # clear flash if it's been set by a previous request and not dismissed by the user
    flash[:error] = nil
    flash[:notice] = nil

    if params[:member_id].blank?
      flash[:error] = "You must select an organization."
    end

    if !user_in_organization? && !flash[:error]
      flash[:error] = "You do not have permission to add this organization."
    end

    if has_already_signed_up? && !flash[:error]
      flash[:notice] = if current_user_is_admin?
        "An organization admin has already added this organization to the waitlist."
      else
        "You have already added this organization to the waitlist."
      end
    end

    unless flash[:error] || flash[:notice]
      if create_early_access_membership
        return render "copilot/fine_tuning_waitlist_signup/success", locals: {
          org_login: this_organization.display_login,
        }
      else
        flash[:error] = "There was a problem adding you to the waitlist."
      end
    end

    render "copilot/fine_tuning_waitlist_signup/join", locals: {
      preview_terms: beta.preview_terms,
      organizations: current_user.organizations,
    }
  end

  private

  # If an admin has already nominated this organization, let's not do it again.
  # However, many different end-users can nominate the same organization - they
  # just can't do it more than once per-user.
  memoize def has_already_signed_up?
    if current_user_is_admin?
      EarlyAccessMembership
        .copilot_customization_waitlist
        .exists?(can_onboard: true, member: this_organization)
    else
      EarlyAccessMembership
        .copilot_customization_waitlist
        .exists?(actor: current_user, member: this_organization)
    end
  end

  memoize def this_organization
    Organization.find_by(id: params[:member_id])
  end

  memoize def current_user_is_admin?
    this_organization&.adminable_by?(current_user)
  end

  def user_in_organization?
    this_organization&.member?(current_user)
  end

  def create_early_access_membership
    membership = EarlyAccessMembership.new(
      member: this_organization,
      actor_id: current_user.id,
      feature_slug: beta.feature_slug,
      survey: survey,
      can_onboard: current_user_is_admin?,
    )

    membership.save_with_survey_answers(survey_answers)
  end

  memoize def survey_answers
    # Since we tell users that signing up for the waitlist requires agreeing to our terms,
    # we find and submit the correct survey response ourselves.
    terms_question = survey.questions.find_by(short_text: "copilot_preview_specific_terms")
    terms_choice = terms_question.choices.find_by(short_text: "agree_copilot_preview_specific_terms")

    terms_survey_answer = {
      question_id: terms_question.id,
      choice_id: terms_choice.id,
    }

    # Add an is_admin field to the survey answers so we can differentiate admin from non-admin requests in the
    # exported survey results CSV
    admin_question = survey.questions.find_by(short_text: "is_admin")
    admin_answer = admin_question.choices.find_by(short_text: "is_admin")
    end_user_answer = admin_question.choices.find_by(short_text: "is_end_user")

    admin_survey_answer = {
      question_id: admin_question.id,
      choice_id: current_user_is_admin? ? admin_answer.id : end_user_answer.id,
      other_text: current_user_is_admin? ? "admin" : "end_user"
    }

    # Add the organization login to the survey answers so we can group by it in the exported survey results CSV
    organization_question = survey.questions.find_by(short_text: "organization_login")
    organization_survey_answer = {
      question_id: organization_question.id,
      choice_id: organization_question.choices.first.id,
      other_text: this_organization.display_login
    }

    [terms_survey_answer, admin_survey_answer, organization_survey_answer]
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    # cap_bypass:to_fix - this controller is using organization
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def ensure_not_proxima
    render_404 if GitHub.multi_tenant_enterprise?
  end

  memoize def beta
    ::Copilot::CustomizationBeta.new
  end

  memoize def survey
    Copilot::CustomizationBetaWaitlistSurvey.find_survey
  end
end
