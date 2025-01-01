# typed: strict
# frozen_string_literal: true

class User
  class RepoCollection

    sig { params(owner: User).void }
    def initialize(owner)
      @owner = owner
    end

    sig { params(resource_name: String).returns(IntegrationInstallation::AbilityCollection) }
    def collection_for(resource_name)
      IntegrationInstallation::AbilityCollection.new(
        parent: @owner,
        name: resource_name,
        ability_type_prefix: Repository::Resources::ALL_ABILITY_TYPE_PREFIX,
      )
    end

    # Internal: An abstract collection, to refer to each repository sub-resource
    # e.g. contents, issues, statuses.
    Repository::Resources.subject_types.each do |resource|
      define_method("#{resource}") do
        owner = instance_variable_get(:@owner)
        T.unsafe(self).collection_for(resource)
      end
    end
  end
end
