# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::Comments
  class Filter
    FILTER_MAP = {
      diff_filter_config: PullRequests::Copilot::CodeReview::Comments::Filters::DiffFilterConfig,
    }.freeze

    sig { params(comments: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def initialize(comments:)
      @comments = comments
      @filters = []
    end

    sig { params(filter_name: Symbol).returns(PullRequests::Copilot::CodeReview::Comments::Filter) }
    def with_filter(filter_name)
      filters << filter_name

      self
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def filter!
      filters.each do |filter|
        filter_class = FILTER_MAP[filter]
        filter_instance = filter_class.new(comments:)

        filter_instance.filter!
      end

      comments
    end

    private

    sig { returns(T::Array[Symbol]) }
    attr_reader :filters

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    attr_accessor :comments
  end
end
