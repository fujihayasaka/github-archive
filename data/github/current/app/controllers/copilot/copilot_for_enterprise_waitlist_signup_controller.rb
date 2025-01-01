# typed: true
# frozen_string_literal: true

class Copilot::CopilotForEnterpriseWaitlistSignupController < ApplicationController
  before_action :login_required, except: [:new]
  before_action :dotcom_required
  before_action :ensure_not_multitenant_enterprise

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
    return redirect_to copilot_for_enterprise_waitlist_signup_join_path if logged_in?

    redirect_to "/features/preview/copilot-enterprise"
  end

  def join # rubocop:todo GitHub/UseRestfulActions
    context_region_title "GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} waitlist"

    render "copilot/copilot_for_enterprise_waitlist_signup/join", locals: {
      survey_choice_detail_links: beta.survey_choice_detail_links,
      preview_terms: beta.preview_terms,
      enterprises: current_user.businesses,
      survey_questions: beta.survey.questions,
      signup_closed: waitlist_signup_closed?
    }
  end

  def create
    return render_404 if waitlist_signup_closed?

    context_region_title "GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} waitlist"

    # clear flash if it's been set by a previous request and not dismissed by the user
    flash[:error] = nil
    flash[:notice] = nil

    if params[:member_id].blank?
      flash[:error] = "You must select an enterprise."
    end

    if !current_user_in_enterprise? && !flash[:error]
      flash[:error] = "You do not have permission to add this enterprise."
    end

    if has_already_signed_up? && !flash[:error]
      flash[:notice] = "The enterprise you've selected has already been added to the waitlist."
    end

    unless flash[:error] || flash[:notice]
      if create_early_access_membership
        return render "copilot/copilot_for_enterprise_waitlist_signup/success", locals: {
          business_slug: this_business.slug,
        }
      else
        flash[:error] = "There was a problem adding you to the waitlist."
      end
    end

    render "copilot/copilot_for_enterprise_waitlist_signup/join", locals: {
      survey_choice_detail_links: beta.survey_choice_detail_links,
      preview_terms: beta.preview_terms,
      enterprises: current_user.businesses,
      survey_questions: beta.survey.questions,
      signup_closed: false
    }
  end

  private

  # If an admin has already nominated this enterprise, let's not do it again.
  # However, many different end-users can nominate the same enterprise - they
  # just can't do it more than once per-user.
  memoize def has_already_signed_up?
    if current_user_is_admin?
      EarlyAccessMembership
        .copilot_for_enterprise_waitlist
        .exists?(can_onboard: true, member: this_business)
    else
      EarlyAccessMembership
        .copilot_for_enterprise_waitlist
        .exists?(actor: current_user, member: this_business)
    end
  end

  def create_early_access_membership
    membership = EarlyAccessMembership.new(
      member: this_business,
      actor_id: current_user.id,
      feature_slug: beta.feature_slug,
      survey: survey,
      can_onboard: current_user_is_admin?
    )

    membership.save_with_survey_answers(survey_answers)
  end

  memoize def copilot_authorizer
    current_copilot_user&.copilot_authorizer_object_no_snippy
  end

  memoize def this_business
    Business.find_by(id: params[:member_id])
  end

  memoize def current_user_is_admin?
    this_business&.adminable_by?(current_user)
  end

  def current_user_in_enterprise?
    this_business&.member?(current_user)
  end

  memoize def survey_answers
    from_form = params[:answers]&.values&.select do |answer|
      next if answer.key?(:other_text) && answer[:other_text].blank?

      answer[:choice_id].present? && answer[:choice_id].to_i > 0
    end&.compact

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

    # Add the enterprise slug to the survey answers so we can group by it in the exported survey results CSV
    business_question = survey.questions.find_by(short_text: "enterprise_slug")
    business_survey_answer = {
      question_id: business_question.id,
      choice_id: business_question.choices.first.id,
      other_text: this_business.slug
    }

    from_form + [admin_survey_answer, business_survey_answer]
  end

  def waitlist_signup_closed?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_enterprise_waitlist_closed, subject: current_user)
  end

  def ensure_not_multitenant_enterprise
    render_404 if GitHub.multi_tenant_enterprise?
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    # cap_bypass:to_fix - this controller is also targeting Business in some actions
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  memoize def beta
    ::Copilot::CopilotForEnterpriseBeta.new
  end

  memoize def survey
    Copilot::CopilotForEnterpriseBetaWaitlistSurvey.find_survey
  end
end
