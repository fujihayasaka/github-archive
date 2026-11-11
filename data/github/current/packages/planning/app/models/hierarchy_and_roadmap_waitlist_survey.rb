# typed: true
# frozen_string_literal: true

class HierarchyAndRoadmapWaitlistSurvey
  SURVEY_SLUG = "hierarchy_and_roadmap_beta_waitlist"

  SURVEY_TITLE = "Tasklists Waitlist"

  sig { returns(T.nilable(Survey)) }
  def self.find_survey
    Survey.find_by(slug: SURVEY_SLUG)
  end

  # Public: Creates the Tasklists beta waitlist survey.
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

    # Tasklists
    q = survey.questions.build(
      text: "Tasklists",
      short_text: "tasklists",
      display_order: display_order += 1,
    )

    q.save! unless dry_run
    q.choices.build(text: "Tasklists allow you to quickly decompose work into sub-tasks, track relationships between items, and show metadata like assignees and labels all within your issues.", short_text: "please")
    q.save! unless dry_run

    survey
  end

  # This is a one-time migration to remove the "roadmap" question from the
  # HierarchyAndRoadmapWaitlistSurvey. Updating the survey rather than recreating
  # it should ensure that we don't delete any survey data.
  # This question is being removed since the roadmap no longer requires a waitlist.
  # This is temporary, and once we fully ship the roadmap, we can remove this method.
  #
  # The reason this isn't being run as a migration is that we want to be able to
  # control exactly when this change will roll out via a production console.
  sig { params(dry_run: T::Boolean).void }
  def self.remove_roadmap_from_survey(dry_run: true)
    survey = find_survey
    return unless survey

    survey.title = SURVEY_TITLE
    survey.save! unless dry_run

    roadmap_question = survey.questions.find_by(short_text: "roadmap")
    return unless roadmap_question

    roadmap_question.hidden = true
    roadmap_question.save! unless dry_run
  end
end
