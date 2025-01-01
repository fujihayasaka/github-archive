# typed: true
# frozen_string_literal: true

class HierarchyAndRoadmapBeta
  attr_reader :allow_org_sign_up, :feature_slug, :feature_name, :feature_icon_path, :sign_up_callout,
    :sign_up_feature_flag, :waitlist, :survey, :survey_header, :survey_choice_detail_links, :survey_flash,
    :survey_flash_link_url

  SurveyChoiceDetailLink = Struct.new(:text, :url, keyword_init: true)

  def initialize
    @allow_org_sign_up = true
    @feature_slug = "hierarchy_and_roadmap"
    @feature_name = "Tasklists"
    @sign_up_callout = %Q[
      Admission to the private beta for tasklists is limited and only available for organizations. You must be an admin to enroll your organization in the waitlist and signing up does not guarantee access.
    ].strip
    @sign_up_feature_flag = :hierarchy_and_roadmap_beta_signup
    @waitlist = EarlyAccessMembership.hierarchy_and_roadmap_waitlist
    @survey_header = "Sign up today for your chance to get early access and give your feedback!"
    @survey = HierarchyAndRoadmapWaitlistSurvey.find_survey
    @survey_flash = "Roadmaps for Projects are now in public beta and no longer require enrolling your organization in the waitlist for access."
    @survey_flash_link_url = "https://docs.github.com/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/customizing-the-roadmap-layout"

    @survey_choice_detail_links = {
      tasklists_please:
        SurveyChoiceDetailLink.new(
          text: "Learn More",
          url: "https://aka.ms/tasklists-beta-info"
        ),
      roadmap_please:
        SurveyChoiceDetailLink.new(
          text: "Learn More",
          url: "https://aka.ms/roadmap-beta-info"
        ),
    }.with_indifferent_access
  end
end
