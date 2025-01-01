# typed: true
# frozen_string_literal: true

class Marketplace::ModelsWaitlistController < ApplicationController
  before_action :login_required, except: [:new]
  before_action :dotcom_required
  before_action :non_emu_required, except: [:new, :join]

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
    return redirect_to marketplace_models_waitlist_join_path if logged_in?

    context_region_title "GitHub Models waitlist"

    render "marketplace/models_waitlist/new"
  end

  def join # rubocop:todo GitHub/UseRestfulActions
    context_region_title "GitHub Models waitlist"

    if current_user_on_waitlist?
      return render "marketplace/models_waitlist/success"
    end

    render "marketplace/models_waitlist/join", locals: {
      preview_terms: beta.preview_terms,
      survey_questions: survey.active_questions,
      emu_user: check_emu,
    }
  end

  def create
    context_region_title "GitHub Models waitlist"

    membership = create_early_access_membership
    if membership
      ProjectNeutronBetaMembershipMailer.waitlist_join(membership).deliver_later
      render "marketplace/models_waitlist/success"
    else
      flash[:error] = "There was a problem adding you to the waitlist."

      render "marketplace/models_waitlist/join", locals: {
        preview_terms: beta.preview_terms,
      }
    end
  end

  private

  def check_emu
    current_user.is_enterprise_managed?
  end

  def current_user_on_waitlist?
    return false unless logged_in?

    EarlyAccessMembership.on_waitlist?(beta.feature_slug, current_user)
  end

  def create_early_access_membership
    return true if current_user_on_waitlist?
    return false if current_user.is_enterprise_managed?

    membership = EarlyAccessMembership.new(
      member_id: current_user.id,
      actor_id: current_user.id,
      feature_slug: beta.feature_slug,
      survey: survey,
    )

    from_form = params[:answers]&.values&.select do |answer|
      next if answer.key?(:other_text) && answer[:other_text].blank?

      answer[:choice_id].present? && answer[:choice_id].to_i > 0
    end&.compact

    membership.save_with_survey_answers(terms_survey_answers + from_form)
    membership
  end

  # Since we tell users that signing up for the waitlist requires agreeing to our terms,
  # we find and submit the correct survey response ourselves.
  memoize def terms_survey_answers
    question = survey.questions.find_by_short_text("github_preview_terms")
    choice = question.choices.find_by_short_text("agree_github_preview_terms")

    [{
      question_id: question.id,
      choice_id: choice.id
    }]
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  memoize def beta
    ::Marketplace::ModelsBeta.new
  end

  memoize def survey
    ::Marketplace::ModelsBetaWaitlistSurvey.find_survey
  end
end
