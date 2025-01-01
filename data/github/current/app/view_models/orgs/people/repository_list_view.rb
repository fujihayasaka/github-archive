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

    if GitHub.flipper[:async_action_or_role_level_for_metrics].enabled?
      # temporary metric to measure the performance of Authorization.service.async_most_capable_action_between
      # observe how this changes as :async_mcab_ability_dependency feature flag is rolled out
      timer = Timer.start
      promises = repositories.map { |repo| repo.async_action_or_role_level_for(person) }
      results = Promise.all(promises).sync
      timer.stop
      if repositories.any?
        tags = {
          "callsite" => "repository_list_view",
          "is_batch" => repositories.size > 1
        }
        GitHub.dogstats.distribution("async_action_or_role_level_for.time", timer.elapsed_ms, tags: tags)
      end
    else
      promises = repositories.map { |repo| repo.async_action_or_role_level_for(person) }
      results = Promise.all(promises).sync
    end
    @loaded_access_levels = Hash[repositories.zip(results)]
  end
end
