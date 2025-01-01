# typed: true
# frozen_string_literal: true

class Trending
  class LanguagesFilterView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TrendingMethods
    attr_reader :language, :since, :context

    def top_ten_selected?
      all_languages? || unknown_language?
    end

    def unknown_link
      unknown_language? ? nil : "unknown"
    end

    def language_link(language)
      selected?(language) ? nil : language.default_alias
    end

    def selected?(language)
      known_language? && language.name == known_language_name
    end

    def select_title
      show_clear_option? ? selected_language : "Languages"
    end

    def show_clear_option?
      known_language? && !top_ten_selected?
    end

    def all_languages?
      language.blank?
    end

    def selected_class(bool)
      "selected" if bool
    end

    def random_protip
      protips.sample
    end

    def protips
      [["recently updated", "updated"],
       ["most starred", "stars"],
       ["most forked", "forks"]]
    end

    def protip_text(tip)
      "Looking for #{tip[0]} #{known_language_name} repositories?"
    end

    def protip_url(tip)
      urls.search_path(q: "stars:>1", s: tip[1], l: default_alias, type: "Repositories")
    end

    def default_alias
      selected_language.try(:default_alias)
    end
  end
end
