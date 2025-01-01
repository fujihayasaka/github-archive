# typed: true
# frozen_string_literal: true

module Codespaces
  module VscsTargetHelper
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Domain::Codespaces }

    def vscs_target
      vscs_target = read_attribute(:vscs_target) || Codespaces::Vscs.default_target
      vscs_target.to_sym
    end
  end
end
