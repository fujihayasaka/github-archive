# typed: true
# frozen_string_literal: true

class Marketplace::ModelsBetaWaitlistSurvey
  SLUG = "project_neutron_playground"

  def self.find_survey
    Survey.find_by(slug: SLUG)
  end

  def self.create_survey(dry_run:)
    survey = Survey.new(
      title: "GitHub Models waitlist",
      slug: SLUG,
    )
    survey.save! unless dry_run

    # Preview specific terms is internal-only and will be filled in via the controller,
    # not by the user - THIS IS NOT SHOWN TO THE USER
    terms_q = survey.questions.build(
      text: "GitHub's preview terms",
      short_text: "github_preview_terms",
      hidden: true,
      display_order: 1,
    )
    terms_q.save! unless dry_run

    terms_c = terms_q.choices.build(
      text: "I accept the GitHub preview terms above",
      short_text: "agree_github_preview_terms",
      display_order: 1,
    )
    terms_c.save! unless dry_run

    # Question 1: User's experience in building GenAI solutions with LLMs
    experience_q = survey.questions.build(
      text: "What level of experience do you have in building GenAI solutions that use large language models (LLMs)?",
      short_text: "genai_experience",
      display_order: 2,
    )
    experience_q.save! unless dry_run

    experience_levels = [
      "Exploration/proof-of-concept",
      "In development",
      "I have built 1 solution that is in production",
      "I have built 2 or more solutions that are in production",
    ]

    experience_levels.each_with_index do |level, index|
      experience_q.choices.build(
        text: level,
        short_text: "exp_level_#{index + 1}",
        display_order: index + 1,
      ).save! unless dry_run
    end

    # Question 2: Main business use case for GenAI applications
    use_case_q = survey.questions.build(
      text: "What is your main business use case for GenAI applications? Please select all that apply.",
      short_text: "genai_use_case",
      display_order: 3,
    )
    use_case_q.save! unless dry_run

    use_cases = [
      "RAG-based chat applications (\"chat with my own data\")",
      "Sentiment analysis",
      "Summarization",
      "Content generation",
      "Entity extraction",
      "Text classification",
      "Image classification",
      "Search",
      "Translation",
      "Other (please specify):"
    ]

    use_cases.each_with_index do |use_case, index|
      use_case_q.choices.build(
        text: use_case,
        short_text: "use_case_#{index + 1}",
        display_order: index + 1,
      ).save! unless dry_run
    end

    survey
  end

  def self.find_or_create_survey!
    find_survey || create_survey(dry_run: false)
  end
end
