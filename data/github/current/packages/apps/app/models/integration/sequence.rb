# typed: true
# frozen_string_literal: true

module Integration::Sequence
  extend T::Helpers
  # Internal: Ensures a sequence is created for the integration.
  #
  # Returns nothing.
  def create_sequence
    GitHub.dogstats.distribution_time("integration.create_sequence.time") do
      ::Sequence.create(self)
      true
    end
  end

  def self.included(base)
    base.send :extend, ClassMethods
  end

  module ClassMethods
    def setup_sequence
      T.bind(self, T.class_of(Integration))
      after_create :create_sequence
    end
  end

  mixes_in_class_methods ClassMethods
end
