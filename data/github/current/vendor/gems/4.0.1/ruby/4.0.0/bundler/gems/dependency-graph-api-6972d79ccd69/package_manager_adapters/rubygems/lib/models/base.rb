require "active_record"

module Models
  class Base < ActiveRecord::Base # rubocop:disable GitHub/RailsApplicationRecord
    self.abstract_class = true
  end
end
