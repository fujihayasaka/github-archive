# typed: true
# frozen_string_literal: true

module ProgrammaticAccess::ResourceListHelpers # rubocop:disable ViewComponent/ComponentsHaveUnitTests
  # Internal: Sort a list of *::Resources.subject_types for
  # by their displayable name for easier user consumption.
  #
  # Example:
  #
  #   >> sort_by_displayed_titles(["metadata", "repository_projects", "repository_hooks"])
  #   => ["repository_hooks", "metadata", "repository_projects"]
  #
  #
  # Returns an Array.
  def self.sort_by_displayed_titles(resources)
    resources.each_with_object({}) do |resource, hash|
      # "Projects" => "repository_projects"
      hash[Permissions::FineGrainedResources::Metadata.title(resource)] = resource
    end.sort.to_h.values
  end
end
