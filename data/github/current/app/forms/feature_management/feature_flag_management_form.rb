# typed: true
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagManagementForm < ApplicationForm
    def initialize(params:)
      @params = params
    end

    form do |f|
      f.text_field(name: :feature_flag_name, label: "Feature Flag Name, must be prefixed with `vexi_sandbox_`", value: @params[:feature_flag_name])
      f.group(layout: :horizontal) do |group|
        group.submit(name: :enable_feature_flag, label: "Enable Feature Flag", scheme: :primary)
        group.submit(name: :disable_feature_flag, label: "Disable Feature Flag", scheme: :danger)
      end
      f.group(layout: :horizontal) do |group|
        group.text_field(name: :add_actors, label: "Add actors, comma separated", value: @params[:add_actors])
        group.text_field(name: :remove_actors, label: "Remove actors, comma separated", value: @params[:remove_actors])
      end
      f.group(layout: :horizontal) do |group|
        group.text_field(name: :add_custom_gates, label: "Add custom gates, comma separated", value: @params[:add_custom_gates])
        group.text_field(name: :remove_custom_gates, label: "Remove custom gates, comma separated", value: @params[:remove_custom_gates])
      end
      f.group(layout: :horizontal) do |group|
        group.text_field(name: :set_percentage_of_actors, label: "Set percentage of actors", type: "number", min: 0, step: 1, max: 100, value: @params[:set_percentage_of_actors])
        group.text_field(name: :set_percentage_of_calls, label: "Set percentage of calls", type: "number", min: 0, step: 1, max: 100, value: @params[:set_percentage_of_calls])
      end
      f.hidden(name: :nav_option, value: "vexi_management")
      f.submit(name: :update_feature_flag, label: "Update Feature Flag")
    end
  end
end
