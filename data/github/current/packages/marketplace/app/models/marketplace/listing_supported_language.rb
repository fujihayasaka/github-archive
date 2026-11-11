# typed: strict
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class Marketplace::ListingSupportedLanguage < ApplicationRecord::Domain::Integrations
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "marketplace_listing_supported_languages"

  belongs_to :listing, class_name: "Marketplace::Listing", foreign_key: "marketplace_listing_id" # rubocop:todo Rails/InverseOf
  destroy_in_background_with :listing
  belongs_to :language, class_name: "LanguageName", foreign_key: "language_name_id" # rubocop:todo Rails/InverseOf

  sig { returns(String) }
  def platform_type_name
    "Language"
  end
end
