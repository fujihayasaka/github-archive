# typed: true
# frozen_string_literal: true

class HydroRepositoryPopulateLabelsJob < Repositories::RepositoryHydroMessageJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :hydro_repository_populate_labels

  sig { void }
  def perform
    return if repository.nil?
    return if Label.where(repository_id: repository.id).any?
    return if T.must(repository.owner).organization? && T.unsafe(repository.owner).user_labels.empty?

    initial_labels = if repository.owner&.organization?
      T.cast(repository.owner, Organization).user_labels.map { |label| label.label_attributes }
    else
      Label.initial_labels
    end

    initial_labels.each do |label_attributes|
      Label.create(repository_id: repository.id, **label_attributes)
    rescue ActiveRecord::RecordNotUnique
      next
    end

    time_since_creation_ms = (Time.zone.now - repository.created_at) * 1000
    GitHub.dogstats.distribution("repository.create.time_to_populate_labels.dist", time_since_creation_ms)
  end
end
