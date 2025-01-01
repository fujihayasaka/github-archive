# typed: strict
# frozen_string_literal: true

module GitHubModels
  class ModelOrder < T::Enum
    enums do
      RecentlyAdded = new
      Popular = new
      Slug = new
    end
  end
end
