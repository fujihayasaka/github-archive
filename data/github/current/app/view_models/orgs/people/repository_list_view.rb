# typed: true
# frozen_string_literal: true

class Orgs::People::RepositoryListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repositories, :person

  # Public: The displayable access level that this person has on a repository.
  #
  # Returns a String.
  def repo_access_level(repo)
    loaded_access_levels[repo].to_s.capitalize
  end

  private

  # Private: Preloads all the access levels for the listed repositories, for the
  #         specified person.
  #
  # Returns a Hash{Repository => Symbol}.
  def loaded_access_levels
    return @loaded_access_levels if defined?(@loaded_access_levels)

    promises = repositories.map { |repo| repo.async_action_or_role_level_for(person) }
    results = Promise.all(promises).sync
    @loaded_access_levels = Hash[repositories.zip(results)]
  end
end
