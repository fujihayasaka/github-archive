# typed: true
# frozen_string_literal: true

module Advisories
  class SeverityScoreComponent < ApplicationComponent
    attr_reader :classes, :field_name_prefix, :hidden, :root_target, :score, :score_action_url, :severity, :show_score_label

    def initialize(classes: "", field_name_prefix:, hidden: false, root_target:, score:, score_action_url:, severity:, show_score_label: true)
      @classes = classes
      @field_name_prefix = field_name_prefix
      @hidden = hidden
      @root_target = root_target
      @score = score
      @score_action_url = score_action_url
      @severity = severity
      @show_score_label = show_score_label
    end
  end
end
