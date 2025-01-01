# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectEvent
      include Platform::Interfaces::Base
      description "Represents an event related to a project on the timeline of an issue or pull request."
      visibility :internal

      # TODO add explanatory comment with link
      def self.add_fields(type_defn)
        type_defn.field :project, Objects::Project, description: "Project referenced by event.", null: true, deprecated: Helpers::ProjectDeprecation::Notice
      end

      add_fields(self)
      def self.included(child_class)
        add_fields(child_class)
      end

      def project
        @object.async_subject.then do |project|
          next unless project

          @context[:permission].typed_can_see?("Project", project).then { |can_read| project if can_read }
        end
      end


      field :was_automated, Boolean, visibility: :internal, method: :automated?, description: "Did this event result from workflow automation?", null: false
    end
  end
end
