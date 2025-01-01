# typed: false
# frozen_string_literal: true

class PageBuildJob < ApplicationJob

  queue_as do
    Page.page_queue.to_s
  end

  class RetryError < StandardError; end
  retry_on RetryError

  def perform(page_id, pusher_id, options = {})
    Failbot.push(app: "pages", job: self.class.name)
    GitHub.logger.info("github pages build request received", {
      "gh.pages.id" => page_id,
      "gh.actor.id" => pusher_id,
      "gh.catalog_service" => "github/pages",
    }) if GitHub.kube?
    return unless page = Page.find_by_id(page_id)
    return unless pusher = User.find_by_id(pusher_id)

    repository = page.repository

    Failbot.push(
      "gh.repo.id" => repository.id,
      "gh.user.id" => repository&.owner&.id,
      "gh.actor.name" => pusher&.login,
    )

    # Don't build pages for users who are required to verify their email address
    if pusher.must_verify_email?
      PagesMailer.build_failure(pusher, repository,
        "You need a verified email address in your GitHub account to publish Pages.\n" +
        "You can verify your email addresses from your Settings page:\n\n" +
        "    #{GitHub.url}/settings/emails").deliver_now
      return
    end
    # If two builds for the same page are attempted we let the first one
    # win without retrying the second.
    unless page.lock_build
      GitHub.logger.info("github pages is locked, skip the build", {
        "gh.pages.id" => page_id,
        "gh.actor.id" => pusher_id,
        "gh.catalog_service" => "github/pages",
      }) if GitHub.kube?
      return
    end

    # If this user isn't spammy (yet), do a quick check of the content
    # of the Repository before we build it. If it's spammy, mark the user as
    # spammy so we can unlock the build and get outta here (below).
    if GitHub.spamminess_check_enabled? && !pusher.spammy?
      begin
        if GitHub::SpamChecker.quick_check_pages_repo(repository) > 35
          GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:pages_repository"]
          pusher.safer_mark_as_spammy(reason: "Pages spam")
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        GitHub.dogstats.increment "pages.spam_check_failed"
        Failbot.report(e, app: "pages")
      end
    end

    # For spammy users, don't even notify them, just bail out here.
    return if GitHub.spamminess_check_enabled? && pusher.spammy?

    builder = GitHub::Pages::Builder.new(
      page,
      pusher,
      GitHub.pages_build_dir,
      git_ref_name: options["git_ref_name"],
    )

    # Don't lock the build for the pusher if the build will use an app token
    # This allows a single pusher to have concurrent builds across multiple pages
    # when the build uses an installation token.
    unless builder.should_use_apps?
      # If the build isn't using an installation token from the Pages App,
      # A valid OAuth token is needed for each page build. We rotate the token
      # during each build (for a given user) so that we don't have to store
      # plaintext tokens in the DB. As a result, we need to ensure that two
      # builds for the same user do not occur simultaneously, as they may end
      # up invalidating the token the other job was using.
      unless page.lock_build_for_pusher(pusher)
        page.unlock_build
        raise RetryError
      end
    end

    build = with_write { builder.call }
    page.unlock_build_for_pusher(pusher)
    page.unlock_build

    requeue_if_changed(
      page,
      build,
      [page_id, pusher_id, { "git_ref_name" => options["git_ref_name"] }],
    )
  rescue Exception => boom # rubocop:todo Lint/GenericRescue
    Failbot.report(
      boom, {
      :app => "pages",
      "gh.pages.id" => page_id,
      "gh.actor.id" => pusher_id,
      "git.ref" => options["git_ref_name"],
      "gh.job.name" => self.class.name,
      "gh.user.id" => repository&.owner&.id,
      "gh.actor.name" => pusher&.login,
      "gh.repo.id" => repository.id
    })
    page.unlock_build_for_pusher(pusher)
    page.unlock_build
  end

  def requeue_if_changed(page, build, args)
    return unless page.present?
    return unless build.present?
    return unless build.commit.present?
    return unless args.present?

    git_ref_name = args.last.is_a?(Hash) ? args.last["git_ref_name"] : nil
    target_oid = page&.pages_ref(git_ref_name)&.target_oid

    # If the site has changed, requeue a page build.
    if build.commit != target_oid
      GitHub.dogstats.increment("pages.requeue.repo_changed")
      PageBuildJob.perform_later(*args)
    end
  end

end
