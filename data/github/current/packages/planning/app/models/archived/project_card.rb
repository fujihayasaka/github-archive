# typed: true
# frozen_string_literal: true

class Archived::ProjectCard < ApplicationRecord::Domain::Projects
  include Archived::Base
  include GitHub::Prioritizable

  belongs_to :column, class_name: "Archived::ProjectColumn", inverse_of: :cards
  belongs_to :project, class_name: "Archived::Project", inverse_of: :cards
  belongs_to :content, class_name: "Issue", foreign_key: :content_id # rubocop:todo Rails/InverseOf

  prioritizable_by subject: :content, context: :column
end
