# typed: strict
# frozen_string_literal: true

# This model is only used for replication for local development
class Language < ApplicationRecord::Domain::Repositories
  belongs_to :language_name
  belongs_to :repository
end
