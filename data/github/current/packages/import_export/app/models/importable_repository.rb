# typed: true
# frozen_string_literal: true

class ImportableRepository < Repository
  include Importable

  has_many :importable_issues

  self.permissions_wrapper_class = Permissions::Attributes::Repository

  def type
    "Repository"
  end

  # Override the hydro context value to map to :REPOSITORY
  def self.hydro_context
    :REPOSITORY
  end

  # Overrides Repository::Sequence
  #
  # Creates sequence based on the Repository object
  # instead of the ImportableRepository object.
  # Returns nothing.
  def create_sequence
    ::Sequence.create(Repository.find_by(id: self.id))
    true
  end
end
