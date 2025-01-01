# typed: true
# frozen_string_literal: true

module Advisories
  class MetricSelectionFieldNextComponent < ApplicationComponent
    attr_reader :metric_sub_category, :metric_selection_classes, :repository
    with_collection_parameter :metric_sub_category

    def initialize(metric_sub_category: {}, metric_selection_classes: "")
      @metric_sub_category = metric_sub_category
      @metric_selection_classes = metric_selection_classes
    end
  end
end
