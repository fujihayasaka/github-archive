# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class IntegrationsLodge < ApplicationRecord::Lodge
      self.abstract_class = true
    end
  end
end
