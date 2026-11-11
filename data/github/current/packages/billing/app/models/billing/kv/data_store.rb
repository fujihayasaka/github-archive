# typed: strict
# frozen_string_literal: true

module Billing
  class Kv
    class DataStore < ApplicationRecord::Domain::Billing
      self.table_name = :billing_key_values
    end
  end
end
