# typed: true
# frozen_string_literal: true

class Copilot::CopilotExtensionsWaitlistSignupController < ApplicationController
  before_action :login_required
  before_action :dotcom_required
  before_action :ensure_not_multitenant_enterprise
  before_action :ensure_feature_enabled
  before_action :ensure_copilot_access

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
    only: [:new]

  delegate :survey, to: :beta

  sig { void }
  def new
    context_region_title "GitHub Copilot Extensions waitlist"

    render_signup_form
  end

  sig { void }
  def create
    context_region_title "GitHub Copilot Extensions waitlist"

    if nominee.blank?
      flash[:error] = "You must select an enterprise or organization to join the waitlist"
      return render_signup_form
    end

    if user_already_signed_up?
      flash[:error] = "You have already signed up for the waitlist"
      return render_signup_form
    end

    unless user_member_of_nominee?
      flash[:error] = "You are not a member of that #{nominee.class.name&.downcase}"
      return render_signup_form
    end

    if create_early_access_membership
      render "copilot/copilot_extensions_waitlist_signup/success", locals: {
        copilot_user: copilot_user, nominee: nominee
      }
    else
      flash[:error] = "There was a problem adding you to the waitlist."
      render_signup_form
    end
  end

  private

  sig { void }
  def render_signup_form
    render "copilot/copilot_extensions_waitlist_signup/new", locals: {
      beta: beta, copilot_user: copilot_user, entities_for_nomination: entities_for_nomination
    }
  end

  sig { void }
  def ensure_not_multitenant_enterprise
    render_404 if GitHub.multi_tenant_enterprise?
  end

  sig { void }
  def ensure_feature_enabled
    render_404 unless current_user.feature_enabled?(:copilot_extensions_waitlist_signup)
  end

  sig { void }
  def ensure_copilot_access
    redirect_to features_copilot_path if [:NO_ACCESS, :ENTERPRISE_MANAGED, :UNKNOWN].include?(copilot_user.access_type)
  end

  sig { returns(::Copilot::User) }
  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  sig { returns(::Copilot::ExtensionsBeta) }
  memoize def beta
    Copilot::ExtensionsBeta.new
  end

  sig { returns(T::Array[T.any(Copilot::Organization, Copilot::Business)]) }
  def entities_for_nomination
    # Enterprises that are giving this user access, as well as standalone organizations that are giving access
    return [] unless copilot_user.has_cfb_access? || copilot_user.has_cfe_access?

    standalone_orgs = copilot_user.copilot_organizations.select { |org| org.business.nil? }

    copilot_user.copilot_businesses + standalone_orgs
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  memoize def nominee
    if copilot_user.has_cfi_access?
      current_user
    else
      return nil unless params[:nominee_slug].present?

      type, slug = params[:nominee_slug].split(":", 2)
      if type == "organization"
        ::Organization.find_by_login(slug)
      elsif type == "enterprise"
        ::Business.find_by(slug: slug)
      end
    end
  end

  sig { returns(T::Boolean) }
  def user_already_signed_up?
    EarlyAccessMembership.copilot_extensions_waitlist.exists?(actor: current_user)
  end

  sig { returns(T::Boolean) }
  def user_member_of_nominee?
    return false unless nominee.present?
    return true unless nominee.is_a?(Organization) || nominee.is_a?(Business)

    T.cast(nominee, T.any(Organization, Business)).member?(current_user)
  end

  sig { returns(T::Boolean) }
  def create_early_access_membership
    membership = EarlyAccessMembership.new(
      member: nominee,
      actor_id: current_user.id,
      feature_slug: Copilot::ExtensionsBeta::FEATURE_SLUG,
      survey: survey,
      can_onboard: actor_is_admin?
    )

    result = membership.save_with_survey_answers(survey_answers)
    if result && !actor_is_admin? && (nominee.is_a?(Organization) || nominee.is_a?(Business))
      T.must(nominee).admins.each do |admin|
        CopilotExtensionsBetaMembershipMailer.notify_admin_about_signup(membership, admin).deliver_later
      end
    end
    result
  end

  sig { returns(T::Boolean) }
  def actor_is_admin?
    return false if nominee.nil?
    return true unless nominee.is_a?(Organization) || nominee.is_a?(Business)

    T.cast(nominee, T.any(Organization, Business)).adminable_by?(current_user)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def survey_answers
    return [] unless nominee

    admin_question = survey.questions.find_by(short_text: "is_admin")
    admin_answer = admin_question.choices.find_by(short_text: "is_admin")
    end_user_answer = admin_question.choices.find_by(short_text: "is_end_user")

    admin_survey_answer = {
      question_id: admin_question.id,
      choice_id: actor_is_admin? ? admin_answer.id : end_user_answer.id,
      other_text: actor_is_admin? ? "admin" : "end_user"
    }

    slug_question = survey.questions.find_by(short_text: "member_slug")
    slug_survey_answer = {
      question_id: slug_question.id,
      choice_id: slug_question.choices.first.id,
      other_text: T.cast(nominee, T.any(User, Organization, Business)).display_login
    }

    type_question = survey.questions.find_by(short_text: "member_type")
    type_survey_answer = {
      question_id: type_question.id,
      choice_id: type_question.choices.first.id,
      other_text: nominee.class.name
    }

    [admin_survey_answer, slug_survey_answer, type_survey_answer]
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    # cap_bypass:to_fix - this controller is also targeting Business in some actions
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
