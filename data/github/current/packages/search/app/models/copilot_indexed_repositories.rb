# typed: true
# frozen_string_literal: true

class CopilotIndexedRepositories < ApplicationRecord::Domain::Copilot
  DEFAULT_COPILOT_INDEXING_QUOTA = 50
  belongs_to :organization
  belongs_to :repository

  attr_accessor :name_validation_only
end
