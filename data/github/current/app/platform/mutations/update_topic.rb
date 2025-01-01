# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTopic < Platform::Mutations::Base
      description "Updates an existing topic."
      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :name, String, "The name of the topic.", required: true
      argument :is_flagged, Boolean, "Indicates whether the topic is flagged.", required: false
      argument :is_featured, Boolean, "Indicates whether the topic is featured.", required: false

      field :topic, Objects::Topic, "The updated topic.", null: true

      def resolve(**inputs)
        topic = Objects::Topic.load_from_global_id(inputs[:name]).sync
        raise Errors::NotFound.new("Invalid topic name '#{inputs[:name]}'") unless topic

        unless inputs[:is_flagged].nil?
          unless context[:viewer].site_admin?
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to " \
                                           "change topic #{topic.name}'s flagged status.")
          end

          topic.flagged = inputs[:is_flagged]
        end

        unless inputs[:is_featured].nil?
          unless context[:viewer].biztools_user? || context[:viewer].site_admin?
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to " \
                                           "change topic #{topic.name}'s featured status.")
          end

          topic.featured = inputs[:is_featured]
        end

        if topic.save
          { topic: topic }
        else
          errors = topic.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not update topic: #{errors}")
        end
      end
    end
  end
end
