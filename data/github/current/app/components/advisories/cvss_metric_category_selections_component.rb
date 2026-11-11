# typed: true
# frozen_string_literal: true

module Advisories
  class CvssMetricCategorySelectionsComponent < ApplicationComponent
    attr_reader :metric_category, :metric, :metric_selection_classes, :repository
    with_collection_parameter :metric

    def initialize(metric:, metric_selection_classes: "")
      @metric = metric
      @metric_selection_classes = metric_selection_classes
    end
  end
end
