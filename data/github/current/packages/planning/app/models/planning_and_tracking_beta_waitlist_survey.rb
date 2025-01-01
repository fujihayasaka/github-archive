# typed: true
# frozen_string_literal: true

class PlanningAndTrackingBetaWaitlistSurvey
  SURVEY_SLUG = "plan_and_track_v2_waitlist"

  SURVEY_TITLE = "GitHub Issues Waitlist"

  sig { returns(T.nilable(Survey)) }
  def self.find_survey
    Survey.find_by(slug: SURVEY_SLUG)
  end

  # Public: Creates the Planning and Tracking beta waitlist survey.
  #
  # Pass force to destroy and re-create the survey.
  # N.B. setting force: true will delete all old survey data, but not any
  # corresponding EarlyAccessMembership.
  sig { params(force: T::Boolean, dry_run: T::Boolean).returns(Survey) }
  def self.create_survey(force: false, dry_run: false)
    if force && survey = find_survey
      survey.destroy
    end

    survey = Survey.new(
      slug: SURVEY_SLUG,
      title: SURVEY_TITLE
    )
    survey.save! unless dry_run

    display_order = 0

    # Build the checkbox question
    q = survey.questions.build(
      text: "GitHub Issues",
      short_text: "GitHub Issues",
      display_order: display_order += 1,
    )

    q.save! unless dry_run
    q.choices.build(text: "Sub-issues, issue types and advanced search.", short_text: "please")
    q.save! unless dry_run

    survey
  end
end
