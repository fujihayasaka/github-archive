# typed: true
# frozen_string_literal: true

class GitHubConnectIndexAllReposJob < ApplicationJob
  queue_as :github_connect

  def perform(_options = {})
    return unless enabled?

    Repository.find_in_batches do |group|
      group.each do |repo|
        send_manifests_to_dependency_graph(repo: repo)
        newsletter_signup_for_repo(repo: repo)
      end
    end
  end

  private

  def enabled?
    GitHub.dotcom_connection_enabled? && GitHub.ghe_content_analysis_enabled?
  end

  def send_manifests_to_dependency_graph(repo:)
    RepositoryDependencyManifestInitializationJob.perform_later(repo.id)
  end

  def newsletter_signup_for_repo(repo:)
    owner = repo.owner
    owners = owner.organization? ? owner.admins : [owner]
    owners.each do |admin|
      with_write { NewsletterSubscription.subscribe(admin, "vulnerability", "weekly", resubscribe: false) }
    end
  end
end
