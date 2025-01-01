# typed: true
# frozen_string_literal: true

class BetaMembershipsController < ApplicationController
  include AccountMembershipHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:signup]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:thanks]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:signup], optional: true

  BETAS = {
    "code-search": BlackbirdSearch::Beta,
    "code-search-code-view": BlackbirdMonolith::Beta,
    # For now this will be overriden by the PlanningAndTrackingBeta class when the FF is enabled
    "issues": HierarchyAndRoadmapBeta,
    "bitbucket-migrations": BitbucketServerMigrations::Beta,
  }

  before_action :login_required, except: :signup
  before_action :beta_required
  before_action :feature_required

  def signup # rubocop:todo GitHub/UseRestfulActions
    render "beta_memberships/signup", locals: { beta: beta }
  end

  def agree # rubocop:todo GitHub/UseRestfulActions
    if current_user.should_verify_email?
      flash[:error] = "Signing up for #{beta.feature_name} requires a verified email address."
      render_email_verification_required
      return
    end

    if params["member_id"] && params["member_id"] == ""
      flash[:error] = "Please select an account."
      redirect_to beta_signup_path
      return
    end

    if beta.feature_slug == "hierarchy_and_roadmap" && params["member_id"]
      member = User.find(params["member_id"])
      unless member.nil?
        # If requested member is an organization and was added by a different admin, add the current user to
        # subscriber cache and go to the "thanks" page. This allows the onboarding mailer to be sent to all
        # interested admins, not just the one who created the first request. Adding a new EarlyAccessMembership record
        # for this organization and feature will fail validation as duplicates are not allowed.
        #
        # The tradeoff here is that we lose whatever form options were selected by the current user, but this is
        # deemed acceptable given time constraints.
        #
        # This is special-cased for the Hierarchy and Roadmap signup page, and is not intended to be a complete
        # solution.
        if has_someone_else_registered_organization?(member) && current_user_is_org_admin?(member)
          EarlyAccessSubscribers.append_subscriber_id(beta.feature_slug, member.id, current_user.id)
          return redirect_to beta_thanks_path(member_id: member.id)
        end
      end
    end

    membership = create_early_access_membership
    pre_release_member = create_pre_release_member

    if membership.persisted? && pre_release_member.persisted?
      GitHub.dogstats.increment("#{beta.feature_slug}.joined_waitlist")

      # add first author to subscriber list
      EarlyAccessSubscribers.append_subscriber_id(beta.feature_slug, T.must(member).id, current_user.id) if beta.feature_slug == "hierarchy_and_roadmap"

      if params[:redirect_back]
        safe_redirect_to params[:redirect_back]
      else
        redirect_to beta_thanks_path(member_id: membership.member_id)
      end
    else
      field_errors = membership.errors.full_messages + pre_release_member.errors.full_messages
      flash[:error] = "Sorry that didn’t work. #{field_errors.to_sentence}."
      redirect_to beta_signup_path(member_id: membership.member_id)
    end
  end

  def thanks # rubocop:todo GitHub/UseRestfulActions
    if beta.waitlist.exists?(member_id: params["member_id"])
      render "beta_memberships/thanks", locals: { beta: beta }
    else
      redirect_to beta_signup_path
    end
  end

  private

  def create_early_access_membership
    # EarlyAccessMemberships also support Business members, but this controller
    # currently only supports setting a specific member_id for Users & Organizations
    member = if params["member_id"]
      User.find(params["member_id"])
    else
      current_user
    end

    membership = EarlyAccessMembership.new(
      member: member,
      actor: current_user,
      feature_slug: beta.feature_slug,
      survey: beta.survey,
    )

    if survey_answers.present?
      membership.save_with_survey_answers(survey_answers)
    else
      membership.save
    end

    membership
  end

  def create_pre_release_member
    attrs = { member_id: current_user.id, actor_id: current_user.id }
    PrereleaseProgramMember.find_by(attrs) || PrereleaseProgramMember.create(attrs)
  end

  # Check whether this member has already been registered by a different administrator
  #
  # This preserves whatever existing checks we do around validation for other situations (e.g. a record was previously
  # created by the same admin) to simply isolate the "another admin is trying to add this same organization" case
  # and allow us to handle this case without rejecting the request.
  def has_someone_else_registered_organization?(member)
    existing_membership = EarlyAccessMembership.find_by(member_id: member.id, feature_slug: beta.feature_slug)
    return false if existing_membership.nil?

    return false if existing_membership.actor_id == current_user.id

    true
  end

  def current_user_is_org_admin?(member)
    return true if member.is_a?(Business) && member.adminable_by?(current_user)

    return true if member.organization? && member.adminable_by?(current_user)

    false
  end

  memoize def survey_answers
    params[:answers]&.values&.select do |answer|
      next if answer.key?(:other_text) && answer[:other_text].blank?

      answer[:choice_id].present?
    end&.compact
  end

  def sign_up_enabled?
    !GitHub.enterprise? &&
      feature_enabled_globally_or_for_current_user?(beta.sign_up_feature_flag)
  end

  def feature_required
    render_404 unless sign_up_enabled?
  end

  def beta_required
    render_404 unless beta
  end

  memoize def beta
    # Temporarily override tasklists for the Planning and Tracking beta
    if feature_enabled_globally_or_for_current_user?(:planning_and_tracking_beta_signup) && params[:beta] == "issues"
      return PlanningAndTrackingBeta.new
    end

    BETAS[params[:beta].to_sym]&.new
  end
end
