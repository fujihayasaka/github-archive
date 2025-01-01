# typed: true
# frozen_string_literal: true

module LegacyImportable
  extend ActiveSupport::Concern

  def importing?
    GitHub.importing?
  end

  class_methods do
    def importing?
      GitHub.importing?
    end
  end
end
