# typed: strict
# frozen_string_literal: true

module Discussions
  class Kv
    class DataStore < ApplicationRecord::Domain::Discussions
      self.table_name = "discussions_key_values"
    end
  end
end
