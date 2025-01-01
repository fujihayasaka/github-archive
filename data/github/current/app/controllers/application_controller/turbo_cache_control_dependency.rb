# typed: true
# frozen_string_literal: true

module ApplicationController::TurboCacheControlDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.cast(self, Class).class_attribute :turbo_cache_control_value

    T.bind(self, T.class_of(ApplicationController))
    helper_method :turbo_cache_control_value
    self.turbo_cache_control_value = "no-preview"
  end

  module ClassMethods
    def turbo_cache_control(value, **options)
      T.bind(self, T.class_of(ApplicationController))

      before_action(options) do
        self.turbo_cache_control_value = value
      end
    end
  end

  mixes_in_class_methods(ClassMethods)
end
