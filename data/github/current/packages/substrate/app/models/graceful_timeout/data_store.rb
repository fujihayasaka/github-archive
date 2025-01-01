# typed: strict
# frozen_string_literal: true

module GracefulTimeout
  class DataStore < ApplicationRecord::Domain::UsersBallast
    self.table_name = "graceful_timeout_key_values"
  end
end
