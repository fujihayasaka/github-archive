# typed: true
# frozen_string_literal: true

module Codespaces
  module VscsTargetDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    include Codespaces::VscsTargetHelper

    requires_ancestor { ActiveModel::Validations }

    included do
      T.bind(self, ActiveModel::Validations::ClassMethods)
      validates_with Codespaces::VscsTargetValidator
    end
  end
end
