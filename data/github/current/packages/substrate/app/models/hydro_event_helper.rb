# typed: false
# frozen_string_literal: true

module HydroEventHelper
  extend ActiveSupport::Concern

  class_methods do
    # Set the hydro event message context attribute to the symbolized class name
    def hydro_context
      name.upcase.to_sym
    end
  end
end
