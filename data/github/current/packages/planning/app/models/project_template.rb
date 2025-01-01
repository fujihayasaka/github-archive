# typed: true
# frozen_string_literal: true

# A superclass for ProjectTemplate objects and the data necessary to create
# ProjectColumns and ProjectWorkflows for a GitHub-provided template
#
# Templates available:
#   "none"                => ProjectTemplate::None (for UI/display only)
#   "basic_kanban"        => ProjectTemplate::BasicKanban
#   "automated_kanban_v2" => ProjectTemplate::AutomatedKanbanV2
#
# Usage:
#   template = ProjectTemplate.load("basic_kanban")
#   project = Project.new
#   project.apply_template(template)
#   project.save
#
#   If you're calling `load` from GraphQL, the `load` method accepts template
#   names as uppercase snake case, aka angry snake case (ex: "BASIC_KANBAN"),
#   using the values from the ProjectTemplate Enum.
#
# To add a new template:
#   1. create a new model under the ProjectTemplate superclass
#   2. include a `build` method that creates all the structures for your template
#         at a minimum, you should have an array of ProjectTemplateColumns
#   3. ** VERY IMPORTANT / DANGER ** add the underscore-ized version of the class
#         name to the `TYPES` list below; this adds your template to the UI for
#         all users to see :tada:
#   4. add the uppercase version of the value you added to `TYPES` to the
#         ProjectTemplate Enum for GraphQL; this makes it possible for users
#         to create projects using your template! :sparkles:
#
class ProjectTemplate
  attr_reader :columns

  # Provided types that build data structures
  # Matches the corresponding template class
  # ex:
  #   "basic_kanban" => ProjectTemplate::BasicKanban
  TYPES = %w[none basic_kanban automated_kanban_v2 automated_reviews_kanban bug_triage].freeze
  DEFAULT = ProjectTemplate::None
  SOURCE_MAPPINGS = {
    "ProjectTemplate::BasicKanban" => 1,
    "ProjectTemplate::AutomatedKanban" => 2,
    "ProjectTemplate::AutomatedReviewsKanban" => 3,
    "ProjectTemplate::AutomatedKanbanV2" => 4,
    "ProjectTemplate::BugTriage" => 5,
  }.freeze

  def initialize
    @columns = []
    build
  end

  def build
    raise NotImplementedError, "Subclasses of ProjectTemplate must define a build method"
  end

  def self.title
    raise NotImplementedError, "Subclasses of ProjectTemplate must define a title class method"
  end

  def column_data
    @columns.map(&:data)
  end

  def self.default?
    self.template_key == DEFAULT.template_key
  end

  # Load the requested template and build the associated objects
  #
  def self.load(template)
    template_klass(template).new
  end

  # Check if a template is valid before creation
  #
  def self.valid?(template)
    TYPES.include?(template&.downcase)
  end

  # Dynamically find the correct class for the type
  #
  def self.template_klass(template)
    raise InvalidTemplateTypeError unless valid?(template)

    case template&.downcase
    when "none"                     then ProjectTemplate::None
    when "basic_kanban"             then ProjectTemplate::BasicKanban
    when "automated_kanban_v2"      then ProjectTemplate::AutomatedKanbanV2
    when "automated_reviews_kanban" then ProjectTemplate::AutomatedReviewsKanban
    when "bug_triage"               then ProjectTemplate::BugTriage
    end
  end

  # UI helper to list all templates.
  #
  def self.list
    TYPES.map { |template| template_klass(template) }
  end

  # Formats the template class into a form-safe string..
  #
  def self.template_key
    self.to_s.sub(/\A(.*?):{2}/, "").underscore.upcase
  end

  # Used when new project creation errors
  #
  def self.selected?(selected_template)
    if selected_template
      template_key == selected_template
    else
      default?
    end
  end

  class InvalidTemplateTypeError < StandardError; end
end
