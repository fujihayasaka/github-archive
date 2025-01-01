# typed: strict
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  # For the purposes of applying a template, a system template just at least needs to have an ID, though
  # in reality this has many properties. See MemexProject::StructureSerializer for serialized properties.
  SystemTemplate = T.type_alias { { id: String } }

  # List of all system-defined templates
  SYSTEM_TEMPLATES = T.let([
    MemexProject::DefaultTemplates::TeamPlanningTemplate,
    MemexProject::DefaultTemplates::FeatureReleaseTemplate,
    MemexProject::DefaultTemplates::KanbanTemplate,
    MemexProject::DefaultTemplates::BugTrackerTemplate,
    MemexProject::DefaultTemplates::IterativeDevelopmentTemplate,
    MemexProject::DefaultTemplates::ProductLaunchTemplate,
    MemexProject::DefaultTemplates::RoadmapTemplate,
    MemexProject::DefaultTemplates::TeamRetrospectiveTemplate,
  ].freeze, T::Array[SystemTemplate])

  # Map of system template IDs to the actual template data
  SYSTEM_TEMPLATE_MAP = T.let(SYSTEM_TEMPLATES.map { |template| [template[:id], template] }.to_h.freeze, T::Hash[String, SystemTemplate])
end
