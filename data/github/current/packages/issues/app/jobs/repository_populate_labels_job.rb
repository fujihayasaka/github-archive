# typed: true
# frozen_string_literal: true

class RepositoryPopulateLabelsJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :repository_populate_labels

  retry_on_dirty_exit

  # Populates a new repository with labels
  #
  # repo_id - The repository id of the repo
  #
  # Returns nothing.
  def perform(repo_id)
    repo = Repository.find_by(id: repo_id)
    return if repo.nil?

    initial_labels = if repo.owner&.organization?
      T.cast(repo.owner, Organization).user_labels.map { |label| label.label_attributes }
    else
      Label.initial_labels
    end

    initial_labels.each do |label_attributes|
      new_label = repo.labels.create(label_attributes)
    rescue ActiveRecord::RecordNotUnique
      next
    end

    time_since_creation_ms = (Time.zone.now - repo.created_at) * 1000
    GitHub.dogstats.distribution("repository.create.time_to_populate_labels.dist", time_since_creation_ms)
  end
end
