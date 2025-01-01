# typed: true
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagEvaluationForm < ApplicationForm
    def initialize(params:)
      @params = params
    end

    form do |f|
      f.text_field(name: :feature_flag_name, label: "Feature Flag Name, must be prefixed with `vexi_sandbox_`", value: @params[:feature_flag_name])
      f.text_field(name: :actors, label: "Actors, comma separated", value: @params[:actors])
      f.hidden(name: :nav_option, value: "vexi_debug")
      f.submit(name: :submit, label: "Evaluate")
    end
  end
end
