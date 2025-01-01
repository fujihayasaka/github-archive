# typed: true
# frozen_string_literal: true

class ImportableProjectColumn < ProjectColumn
  include Importable

  belongs_to :project, class_name: "ImportableProject", inverse_of: :columns, foreign_key: :project_id
  has_many :cards, class_name: "ImportableProjectCard", inverse_of: :column, foreign_key: :column_id

  def type
    "ProjectColumn"
  end
end
