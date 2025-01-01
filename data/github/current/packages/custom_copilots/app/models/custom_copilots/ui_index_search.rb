# typed: strict
# frozen_string_literal: true

module CustomCopilots
  class UIIndexSearch

    # Represents valid search categories for memex index pages
    class Categories < T::Enum
      enums do
        # All custom copilots
        All = new(:all)
        # Projects created by user
        CreatedByMe = new(:created_by_me)
      end
    end

    sig do
      params(
        category: CustomCopilots::UIIndexSearch::Categories,
      ).returns(String)
    end
    def self.get_search_category_title(category:)
      str = case category
      when CustomCopilots::UIIndexSearch::Categories::All
        "All Copilot Spaces"
      when CustomCopilots::UIIndexSearch::Categories::CreatedByMe
        "Created by me"
      end
    end

    sig { returns String }
    def self.all_title
      self.get_search_category_title(category: CustomCopilots::UIIndexSearch::Categories::All)
    end

    sig { returns String }
    def self.created_by_me_title
      self.get_search_category_title(category: CustomCopilots::UIIndexSearch::Categories::CreatedByMe)
    end
  end
end
