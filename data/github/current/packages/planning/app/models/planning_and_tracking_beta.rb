# typed: true
# frozen_string_literal: true

class PlanningAndTrackingBeta
  WAITLIST_CLOSED_LEARN_MORE_HTML = GitHub::HTMLSafeString.make(
    "See how to use GitHub for project planning with " \
    "<a href='https://github.com/features/issues' class='Link--inTextBlock'>GitHub Issues and Projects</a>, " \
    "check out what's new in the " \
    "<a href='https://github.blog/changelog/?label=projects-and-issues' class='Link--inTextBlock'>changelog</a> " \
    "and what's coming up on the " \
    "<a href='https://github.com/orgs/github/projects/4247/views/1' class='Link--inTextBlock'>roadmap</a>, " \
    "and learn more in " \
    "<a href='https://docs.github.com/issues' class='Link--inTextBlock'>our GitHub Issues documentation</a>."
  )

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

  # Indicates whether the waitlist for this beta is currently closed to new sign‑ups.
  # When `true`, the closed waitlist content will be shown instead of the sign‑up form.
  def waitlist_closed?
    true
  end

  def waitlist_closed_title
    "#{@feature_name} is now generally available"
  end

  def waitlist_closed_description
    "The waitlist is now closed as sub-issues, issue types, and advanced search are generally available."
  end

  def waitlist_closed_learn_more_html
    WAITLIST_CLOSED_LEARN_MORE_HTML
  end
end
