# typed: strict
# frozen_string_literal: true

module TrustSafety
  class KV
    class DataStore < ApplicationRecord::Domain::Spam
      self.table_name = "trust_safety_key_values"
    end
  end
end
