# typed: false
# frozen_string_literal: true

class Trending
  module TrendingMethods
    module IndexContext
      def trending_path(view, options)
        view.trending_index_path(options)
      end
      module_function :trending_path
    end

    module DevelopersContext
      def trending_path(view, options)
        view.trending_developers_path(options)
      end
      module_function :trending_path
    end

    def selected_language
      if language
        unknown_language? ? "Unknown" : Linguist::Language[language]
      else
        nil
      end
    end

    def trending_path(view, options)
      context.trending_path(view, options)
    end

    def known_language?
      selected_language && selected_language != "Unknown"
    end

    def unknown_language?
      language == "unknown"
    end

    def known_language_name
      selected_language.name if known_language?
    end

    def date_options
      {
        "daily"   => ["today",      1.day.ago],
        "weekly"  => ["this week",  7.days.ago],
        "monthly" => ["this month", 1.month.ago],
      }
    end

    def since_time
      date_options[since][1]
    end

    def period
      date_options[since][0]
    end

    def title_text(type)
      "Trending #{known_language_name} #{type} on #{GitHub.flavor} #{period}"
    end
  end
end
