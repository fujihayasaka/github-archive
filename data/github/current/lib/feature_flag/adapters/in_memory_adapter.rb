# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Adapters
    class InMemoryAdapter < Vexi::Adapters::InMemoryAdapter
      include TestAdapter
    end
  end
end
