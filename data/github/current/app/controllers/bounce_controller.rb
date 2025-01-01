# typed: true
# frozen_string_literal: true

class BounceController < ApplicationController
  # CAP not required, this only redirects to a static page for non-employees
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index, :support_bounce]

  def index
    safe_bounce_redirect_to params[:to], status: 301
  end

  # Bounces support users to the corresponding support thread in the archive
  # repo and normal users to the contact page.  Used for URLS like:
  # http://support.github.com/discussions/sales/658-interest-in-githubfi
  def support_bounce # rubocop:todo GitHub/UseRestfulActions
    if employee? && !params[:thread].nil?
      thread_number = params[:thread].to_i
      thread_shard = "%02d" % (thread_number / 1000).ceil
      thread_path = "#{params[:category]}/#{thread_shard}/#{thread_number}.md"
      safe_bounce_redirect_to "/github/tender-archive/blob/master/archive/#{thread_path}", status: 301
    else
      safe_bounce_redirect_to "/contact", status: 301
    end
  end

  private

  # All URLs that we should allow bounce redirection to.
  #
  # Returns an array of allowed domains
  ALLOWED_BOUNCE_HOSTS = [
    "github.com",
    "docs.github.com",
    "windows.github.com",
    "mac.github.com",
    "shop.github.com",
    "pages.github.com",
    "gist.github.com",
    "jobs.github.com",
    "raw.github.com",
    "www.gitready.com",           # /guides/put-your-git-branch-name-in-your-shell-prompt
    "textile.thresholdstate.com", # /guides/textile-formatting
    "ozmm.org",                   # /guides/disaster-faq-what-to-do-when-github-goes-bad
    "wiki.eclipse.org",           # /guides/using-the-egit-eclipse-plugin-with-github
    "gitready.com",               # /guides/put-your-git-branch-name-in-your-shell-prompt
    "education.github.com",
    "developer.github.com",
    "training.github.com",
    "services.github.com",
    "pages-auth.github.com",
    GitHub.gist_host_name,
    GitHub.host_name,
    GitHub.classroom_host,
  ].freeze

  # Used to redirect to a URL given in a param.  We only want to redirect to
  # trusted offsite locations.
  #
  # to      - String URL, usually from params[:to]
  # options - Optional Hash passed to #redirect_to.
  #           :status   - The HTTP status of the redirection (default: 302)
  #
  # Returns nothing.
  def safe_bounce_redirect_to(to, options = {})
    safe_redirect_to(to, options.merge(allow_hosts: ALLOWED_BOUNCE_HOSTS))
  end
end
