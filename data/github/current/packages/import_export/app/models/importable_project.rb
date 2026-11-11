# typed: true
# frozen_string_literal: true

class ImportableProject < Project
  include Importable

  has_many :columns, class_name: "ImportableProjectColumn", inverse_of: :project, foreign_key: :project_id
  has_many :cards, class_name: "ImportableProjectCard", inverse_of: :project, foreign_key: :project_id

  def type
    "Project"
  end
end
