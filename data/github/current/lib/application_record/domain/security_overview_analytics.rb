# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class SecurityOverviewAnalytics < ApplicationRecord::SecurityOverviewAnalytics
      self.abstract_class = true
    end
  end
end
