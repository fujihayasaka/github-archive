# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldRepositoryValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :repository

  def initialize(repository, item, field)
    super(item, field)
    @repository = repository
    @platform_type_name = "ProjectV2ItemFieldRepositoryValue"
  end
end
