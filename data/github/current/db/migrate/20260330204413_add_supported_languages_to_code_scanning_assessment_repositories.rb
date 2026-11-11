# typed: true
# frozen_string_literal: true

class AddSupportedLanguagesToCodeScanningAssessmentRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    add_column :code_scanning_assessment_repositories, :supported_languages, :json, null: true
  end
end
