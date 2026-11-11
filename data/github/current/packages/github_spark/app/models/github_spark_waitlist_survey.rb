# typed: true
# frozen_string_literal: true

class GitHubSparkWaitlistSurvey
  SLUG = "github_spark"

  def self.find_survey
    Survey.find_by(slug: SLUG)
  end

  def self.create_survey(dry_run:)
    survey = Survey.new(
      title: "GitHub Spark waitlist",
      slug: SLUG,
    )
    survey.save! unless dry_run

    # Preview specific terms is internal-only and will be filled in via the controller,
    # not by the user
    terms_q = survey.questions.build(
      text: "GitHub Next pre-release terms",
      short_text: "github_next_prerelease_terms",
      hidden: true,
      display_order: 1,
    )
    terms_q.save! unless dry_run

    terms_c = terms_q.choices.build(
      text: "I accept the GitHub Next pre-release terms above",
      short_text: "agree_github_next_prerelease_terms",
      display_order: 1,
    )
    terms_c.save! unless dry_run

    survey
  end

  def self.find_or_create_survey!
    find_survey || create_survey(dry_run: false)
  end
end
