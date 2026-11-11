# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module TopicAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry with a topic."


        field :topic_name, String, null: true, description: "The name of the topic added to the repository"
        def topic_name
          @object.get :topic
        end

        field :topic, Platform::Objects::Topic, null: true, description: "The name of the topic added to the repository"
        def topic
          Loaders::ActiveRecord.load(::Topic, @object.get(:topic_id))
        end

        # internal only

        field :topic_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the added topic"
        def topic_database_id
          @object.get :topic_id
        end

        url_fields prefix: :topic, null: true, description: "The HTTP URL for this topic.", visibility: :internal do |audit_entry|
          Loaders::ActiveRecord.load(::Topic, audit_entry.get(:topic_id)).then do |topic|
            if topic.present?
              path = if GitHub.enterprise?
                "/search?q=topic%3A{topic}&type=Repositories"
              else
                "/topics/{topic}"
              end
              template = Addressable::Template.new(path)
              template.expand(topic: topic.name)
            end
          end
        end
      end
    end
  end
end
