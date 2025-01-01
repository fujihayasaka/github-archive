# typed: true
# frozen_string_literal: true

module GitHub
  module ParameterFilter
    extend self

    def create(filter_parameters: Rails.application.config.filter_parameters)
      ActiveSupport::ParameterFilter.new(filter_parameters)
    end
  end
end
