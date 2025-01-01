# typed: true
# frozen_string_literal: true

class ImportableProjectCard < ProjectCard
  include Importable

  belongs_to :project, class_name: "ImportableProject", inverse_of: :cards, foreign_key: :project_id
  belongs_to :column, class_name: "ImportableProjectColumn", inverse_of: :cards, foreign_key: :column_id

  def type
    "ProjectCard"
  end
end
