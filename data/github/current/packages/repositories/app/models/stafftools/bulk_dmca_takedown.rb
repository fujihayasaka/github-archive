# typed: false
# frozen_string_literal: true

module Stafftools
  class BulkDmcaTakedown < ApplicationRecord::Collab
    include Permissions::Attributes::Wrapper
    self.permissions_wrapper_class = Permissions::Attributes::BulkDmcaTakedown

    enum :status, {
      not_started: 1,
      queued: 2,
      running: 3,
      success: 4,
      error: 5,
    }
    MAX_REPOS = 500

    has_many :bulk_dmca_takedown_repositories, class_name: "Stafftools::BulkDmcaTakedownRepository"
    has_many :repositories, class_name: "::Repository", through: :bulk_dmca_takedown_repositories, disable_joins: true
    belongs_to :disabling_user, class_name: "::User"

    validate :number_of_repos_cannot_exceed_max
    validates_presence_of :disabling_user
    validates_presence_of :notice_public_url
    validates :notice_public_url, format: { with: GitRepositoryAccess::TAKEDOWN_URL_FORMAT, message: "Invalid takedown notice url" }
    validates_presence_of :repositories

    # Get BulkDmcaTakedowns for a repo, across databases, chainable with status enum methods.
    scope :for_repo, lambda { |repo|
      possibles = Stafftools::BulkDmcaTakedownRepository.where(repository_id: repo.id).pluck(:bulk_dmca_takedown_id)
      where(id: possibles)
    }

    # Create a new instance from a Stafftools::BulkDmcaTakedown::Notice
    def self.from_notice(notice, user)
      new({ repositories: notice.repositories,
            disabling_user: user,
            notice_public_url: notice.public_url,
      })
    end

    # Find any BulkDmcaTakedowns associated with the given repo that
    # are in the status of queued and change status to running
    def self.set_running_state(repo)
      for_repo(repo).queued.each do |bulk_takedown|
        bulk_takedown.update(status: :running)
        bulk_takedown.notify_socket_subscribers
      end
    end

    # Find any BulkDmcaTakedowns associated with the given repo that
    # are in the status of running and check for successful completion
    # of all takedowns or error, if not done do nothing.
    def self.notify_job_done(repo)
      for_repo(repo).includes(:repositories).running.each do |bulk_takedown|
        if bulk_takedown.all_repos_disabled?
          bulk_takedown.update(status: :success)
        else
          bulk_takedown.update(status: :error) if bulk_takedown.error_suspected?
        end
        bulk_takedown.notify_socket_subscribers
      end
    end

    # Enqueues all the takedown jobs
    def execute
      update(status: :queued)
      repositories.each do |repo|
        repo.access.dmca_takedown(disabling_user, notice_public_url)
      end
      notify_socket_subscribers
    end

    # Return the job status and access status of each
    # repo that was requested to be taken down.
    def takedown_status
      repositories.inject({}) do |hash, repo|
        hash[repo.id] = Stafftools::DisableRepositoryAccessStatus.new(repo).to_hash
        hash
      end
    end

    # Is everything taken down, that was requested?
    def all_repos_disabled?
      all_disabled = true
      takedown_statuses.each do |status|
        unless status.repository_disabled?
          all_disabled = false
          break
        end
      end
      all_disabled
    end

    # Check to see if a error possibly occurred during the
    # takedown process
    def error_suspected?
      error = false
      takedown_statuses.each do |status|
        if status.error_suspected?
          error = true
          break
        end
      end
      error
    end

    def notify_socket_subscribers
      channel = GitHub::WebSocket::Channels.bulk_takedown_status(self)
      GitHub::WebSocket.notify_bulk_dmca_takedown_channel(self, channel, takedown_status)
    end

    private

    def takedown_statuses
      repositories.map do |repo|
        Stafftools::DisableRepositoryAccessStatus.new(repo)
      end
    end

    def number_of_repos_cannot_exceed_max
      if repositories&.size > MAX_REPOS
        errors.add(:repositories, "can't exceed #{MAX_REPOS} repos")
      end
    end
  end
end
