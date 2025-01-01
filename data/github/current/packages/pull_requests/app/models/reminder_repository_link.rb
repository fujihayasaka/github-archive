# typed: true
# frozen_string_literal: true

class ReminderRepositoryLink < ApplicationRecord::Collab
  belongs_to :reminder
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
end
