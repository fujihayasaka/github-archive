# typed: strict
# frozen_string_literal: true

module Feeds
  class KV
    class DataStore < ApplicationRecord::Domain::UsersBallast
      self.table_name = "feeds_key_values"
    end
  end
end
