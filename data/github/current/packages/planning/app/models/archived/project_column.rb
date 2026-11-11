# typed: true
# frozen_string_literal: true

class Archived::ProjectColumn < ApplicationRecord::Domain::Projects
  include Archived::Base
  include GitHub::Prioritizable::Context
  include GitHub::Tracing

  # rubocop:todo Rails/InverseOf
  has_many :cards, class_name: "Archived::ProjectCard", foreign_key: :column_id, dependent: :delete_all
  # rubocop:enable Rails/InverseOf
  belongs_to :project, class_name: "Archived::Project"

  prioritizes :cards, with: :cards

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }
end
