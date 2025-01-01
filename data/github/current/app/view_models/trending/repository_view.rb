# typed: true
# frozen_string_literal: true

class Trending
  class RepositoryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TrendingMethods

    attr_reader :repo, :scores, :since

    def stars
      scores[:stars][:total] if scores && scores.key?(:stars)
    end

    def forks
      scores[:forks][:total] if scores && scores.key?(:forks)
    end

    def contributors
      @contributors ||= begin
        response = repo.contributors
        if response.computed?
          response.value.first(5)
        else
          response.value
        end
      end
    end

    def star_count
      "#{helpers.number_with_delimiter(stars)} stars #{period}" if stars
    end
  end
end
