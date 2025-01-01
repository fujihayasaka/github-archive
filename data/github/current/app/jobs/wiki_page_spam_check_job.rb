# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class WikiPageSpamCheckJob < ApplicationJob
  queue_as :spam

  retry_on_dirty_exit

  attr_reader :owner
  attr_reader :page
  attr_reader :repo
  attr_reader :repo_path
  attr_reader :user
  attr_reader :wiki

  around_enqueue do |_job, block|
    if GitHub.spamminess_check_enabled?
      block.call
    end
  end

  # options = {:current_user => current_user,
  #            :repo_path => current_repository.nwo,
  #            :page_id => @page.to_param}
  def perform(options = nil)
    return unless GitHub.spamminess_check_enabled?

    options ||= {}
    options = options.stringify_keys
    @user = User.find_by_login(options["current_user"])
    @repo_path = options["repo_path"]
    @repo  = Repository.nwo(repo_path)
    @owner = @repo.owner
    @wiki  = @repo.unsullied_wiki
    @page  = @wiki.pages.find(options["page_id"], options["version"] || @wiki.default_oid)

    begin
      original_component = GitHub.component
      GitHub.component = :resque_wiki_page_spam_check

      Failbot.push(
        job: self.class.name,
        owner: owner.try(:login),
        repo_id: repo&.id,
        page_id: page.to_param,
        user: user.try(:login),
      )

      return if repo.nil?

      # We shouldn't get private Repo wikis queued, but let's check anyway
      return if repo.private?

      # If User is already spammy, or can't be, then our work here is done.
      return if user.spammy? || !user.can_be_flagged?

      # Can't check a page that isn't there. How this happens I don't know.
      return if page.nil?

      GitHub.dogstats.time "spam.jobs.check_for_spam", tags: ["class:wiki_page"] do
        with_write { GitHub::SpamChecker.test_wiki_page(page, user, repo) }
      end
    ensure
      GitHub.component = original_component
    end
  end
end
