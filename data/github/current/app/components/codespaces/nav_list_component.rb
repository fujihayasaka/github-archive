# typed: true
# frozen_string_literal: true

class Codespaces::NavListComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :query, :selected_item_id

  def initialize(query: nil, selected_item_id: :all)
    @query = query
    @selected_item_id = selected_item_id
  end

  # Return array of all repositories (codespaces.repository) and quantity of (published) codespaces for each.
  # Sort in order by: (1) number of codespaces, (2) owner of repo, (3) name of repo.
  memoize def repositories_and_counts
    @query.codespaces
          .reject(&:unpublished?)
          .group_by(&:repository)
          .transform_values(&:count)
          .sort do |rc1, rc2|
            repo1, count1 = rc1
            repo2, count2 = rc2
            [count2, repo1.name_with_display_owner] <=> [count1, repo2.name_with_display_owner]
          end
  end

  memoize def unpublished_codespaces
    @query.codespaces.select(&:unpublished?)
  end
end
