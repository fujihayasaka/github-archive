# typed: true
# frozen_string_literal: true

class PlanningAndTrackingBeta
  attr_reader :allow_org_sign_up, :feature_slug, :feature_name, :feature_name_with_description, :feature_icon_path,
    :sign_up_callout, :sign_up_feature_flag, :waitlist, :survey, :survey_header, :survey_choice_detail_links,
    :hide_survey_single_checkbox

  def initialize
    @allow_org_sign_up = true
    @feature_slug = "plan_and_track_v2"
    @feature_name = "GitHub Issues"
    @feature_name_with_description = "GitHub Issues: Sub-issues, issue types and advanced search"
    @sign_up_callout = %Q[
      Admission to the GitHub Issues: Sub-issues, issue types and advanced search beta is limited and only available for organizations. You must be an admin to enroll your organization and signing up does not guarantee access.
    ].strip
    # A short url to the changelog that we can update in the future
    @changelog_link_url = "https://gh.io/AAseszl"
    @sign_up_feature_flag = :planning_and_tracking_beta_signup
    @waitlist = EarlyAccessMembership.plan_and_track_v2_waitlist
    @survey_header = "Sign up today for your chance to get early access and give your feedback!"
    @survey = PlanningAndTrackingBetaWaitlistSurvey.find_survey
    @hide_survey_single_checkbox = true
    @preview_type = "public beta"
  end

  def changelog_link_url
    @changelog_link_url
  end

  def preview_type
    @preview_type
  end
end
