# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  self.table_name_prefix = "dependabot_" if Dependabot.enterprise?

  connects_to database: { writing: :primary, reading: :reading }
end
