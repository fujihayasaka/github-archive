# typed: true
# frozen_string_literal: true

class User
  class RepoCollection
    def initialize(owner)
      @owner = owner
    end

    # Internal: An abstract collection, to refer to each repository sub-resource
    # e.g. contents, issues, statuses.
    Repository::Resources.subject_types.each do |resource|
      define_method("#{resource}") do
        IntegrationInstallation::AbilityCollection.new(
          parent: @owner,
          name: resource,
          ability_type_prefix: Repository::Resources::ALL_ABILITY_TYPE_PREFIX,
        )
      end
    end
  end
end
