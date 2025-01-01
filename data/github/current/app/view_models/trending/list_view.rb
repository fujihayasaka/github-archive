# typed: true
# frozen_string_literal: true

class Trending
  class ListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TrendingMethods
    attr_reader :language, :since, :context
  end
end
