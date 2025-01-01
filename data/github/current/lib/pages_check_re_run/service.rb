# typed: false
# frozen_string_literal: true

module PagesCheckReRun
  class Service
    CHECK_FAILURE_TITLE = "GitHub Pages failed to build your site."

    def self.run(check_run_id, repository_id, actor_id)
      return false if check_run_id.blank? || repository_id.blank? || actor_id.blank?
      return false unless GitHub.pages_github_app.present?
      check_run = CheckRun.find_by(id: check_run_id, repository_id: repository_id)
      actor = User.find_by(id: actor_id)

      return false unless check_run && actor
      check_suite = check_run.check_suite
      integration_id = check_suite.github_app.id

      return false unless integration_id == GitHub.pages_github_app.id
      Failbot.push(
        "gh.actor.id" => actor_id,
        "gh.pages.check.run.id" => check_run_id,
        "gh.pages.integration.id" => integration_id,
      )
      check_suite.repository.rebuild_pages(actor, check_suite.head_sha)

      GitHub.dogstats.increment("pages.github_check_run.re_run", tags: ["status:success"])
      true
    rescue Page::PageBuildFailed => error
      Failbot.report(error)
      create_failed_check_run(check_suite, actor_id, error.message)
      GitHub.dogstats.increment("pages.github_check_run.re_run", tags: ["status:failed"])
      false
    end

    def self.create_failed_check_run(check_suite, actor_id, error)
      check_suite.check_runs.create!(
        creator_id: actor_id,
        name: GitHub.pages_check_run_name,
        status: :completed,
        conclusion: :failure,
        started_at: Time.now.utc,
        completed_at: Time.now.utc,
        details_url: GitHub.pages_help_url,
        title: CHECK_FAILURE_TITLE,
        summary: error,
        repository: check_suite.repository,
      )
      true
    rescue ActiveRecord::RecordInvalid => error
      Failbot.report(error)
      false
    end
  end
end
