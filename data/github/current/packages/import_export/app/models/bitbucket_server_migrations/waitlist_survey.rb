# typed: strict
# frozen_string_literal: true

module BitbucketServerMigrations
  class WaitlistSurvey
    SURVEY_SLUG = T.let("bitbucket_server_migrations_waitlist".freeze, String)

    sig { returns(T.nilable(Survey)) }
    def self.find_survey
      ::Survey.find_by(slug: SURVEY_SLUG)
    end

    sig { params(force: T::Boolean, dry_run: T::Boolean).returns(Survey) }
    def self.create_survey(force: false, dry_run: false)
      if force && survey = find_survey
        survey.destroy
      end

      survey = Survey.new(
        slug: SURVEY_SLUG,
        title: "Bitbucket Server Migrations Waitlist Survey",
      )
      survey.save! unless dry_run

      display_order = 0

      # Question 1
      q = survey.questions.build(
        text: "Which version of Bitbucket are you using?",
        short_text: "bitbucket_version",
        display_order: 1,
      )

      q.save! unless dry_run
      q.choices.build(text: "Bitbucket Cloud", short_text: "bitbucket_cloud", display_order: 1)
      q.choices.build(text: "Bitbucket Server", short_text: "bitbucket_server", display_order: 2)
      q.choices.build(text: "Bitbucket Data Center", short_text: "bitbucket_data_center", display_order: 3)
      q.save! unless dry_run

      # Question 2
      q = survey.questions.build(
        text: "How many repositories do you have in Bitbucket?",
        short_text: "bitbucket_repos_count",
        display_order: 2,
      )

      q.save! unless dry_run
      q.choices.build(text: "1-10", short_text: "1-10", display_order: 1)
      q.choices.build(text: "11-50", short_text: "11-50", display_order: 2)
      q.choices.build(text: "51-100", short_text: "51-100", display_order: 3)
      q.choices.build(text: "101-250", short_text: "101-500", display_order: 4)
      q.choices.build(text: "251-1000", short_text: "251-1000", display_order: 5)
      q.choices.build(text: "1000+", short_text: "1000+", display_order: 6)
      q.save! unless dry_run

      # Question 3
      q = survey.questions.build(
        text: "How many team members do you have using Bitbucket?",
        short_text: "team_members_count",
        display_order: 3,
      )

      q.save! unless dry_run
      q.choices.build(text: "Just me", short_text: "Just me", display_order: 1)
      q.choices.build(text: "2-10", short_text: "2-10", display_order: 2)
      q.choices.build(text: "11-50", short_text: "11-50", display_order: 3)
      q.choices.build(text: "51-100", short_text: "51-100", display_order: 4)
      q.choices.build(text: "101-250", short_text: "101-500", display_order: 5)
      q.choices.build(text: "251-1000", short_text: "251-1000", display_order: 6)
      q.choices.build(text: "1000+", short_text: "1000+", display_order: 7)
      q.save! unless dry_run

      # Question 4
      q = survey.questions.build(
        text: "Which of the following best describes your job role?",
        short_text: "job_role_other",
        display_order: 4,
      )
      q.save! unless dry_run
      q.choices.build(text: "Security Engineer", short_text: "security_engineer", display_order: 1)
      q.choices.build(text: "Software Engineer", short_text: "software_engineer", display_order: 2)
      q.choices.build(text: "Engineering Manager", short_text: "engineering_manager", display_order: 3)
      q.choices.build(text: "Team Lead", short_text: "team_lead", display_order: 4)
      q.choices.build(text: "Director of Engineering", short_text: "director_of_engineering", display_order: 5)
      q.choices.build(text: "Chief Technology Officer", short_text: "chief_technology_officer", display_order: 6)
      q.choices.build(text: "Product Manager", short_text: "product_manager", display_order: 7)
      q.choices.build(text: "IT Administrator", short_text: "it_administrator", display_order: 8)
      q.choices.build(text: "Other", short_text: "other", display_order: 9)
      q.save! unless dry_run

      survey
    end
  end
end
