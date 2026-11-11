# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class MilestoneImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        Milestone.create! do |milestone|
          milestone.repository = model_from_source_url!(attributes["repository"])
          milestone.created_by = model_from_source_url!(attributes["user"]) || milestone.repository&.owner
          milestone.title = attributes["title"]
          milestone.description = attributes["description"]
          milestone.state = attributes["state"]
          milestone.due_on = attributes["due_on"]
          milestone.created_at = attributes["created_at"]
        end
      end
    end
  end
end
