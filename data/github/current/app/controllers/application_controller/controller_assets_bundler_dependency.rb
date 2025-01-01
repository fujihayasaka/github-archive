# typed: true
# frozen_string_literal: true

# Used to define in the controller what asset tags you want rendered
#
# example:
#### adds admin stylesheet name to the array
# class AdminController < ApplicationController
#   stylesheet_bundle :admin
# end
#
#### creates styletags for all the stylesheets that are in the array
# (In layouts/application.html.erb)
# <%= include_controller_stylesheet_bundles %>
#
module ApplicationController::ControllerAssetsBundlerDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, Class)
    class_attribute :stylesheet_bundles
    class_attribute :javascript_bundles

    T.bind(self, T.class_of(ApplicationController))
    helper_method :stylesheet_bundles
    helper_method :javascript_bundles

    self.stylesheet_bundles = Set.new
    self.javascript_bundles = Set.new
  end

  module ClassMethods
    def stylesheet_bundle(*sources, **options)
      T.bind(self, T.class_of(ApplicationController))

      before_action(options) do
        self.stylesheet_bundles += sources.map(&:to_sym).to_set
      end
    end

    def javascript_bundle(*sources, **options)
      T.bind(self, T.class_of(ApplicationController))

      before_action(options) do
        self.javascript_bundles += sources.map(&:to_sym).to_set
      end
    end
  end

  mixes_in_class_methods(ClassMethods)
end
