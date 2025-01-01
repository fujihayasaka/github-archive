# typed: true
# frozen_string_literal: true

module Wiki
  class CompareView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :comparison

    def page_title
      comparison.page ? "Compare: #{comparison.page.title}" : "History"
    end

    def show_new_button?
      !comparison.repository.locked_on_migration? && !comparison.repository.archived? && comparison.repository.wiki_writable_by?(current_user)
    end
  end
end
