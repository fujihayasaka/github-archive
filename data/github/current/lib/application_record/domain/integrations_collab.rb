# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class IntegrationsCollab < ApplicationRecord::Collab
      self.abstract_class = true
    end
  end
end
