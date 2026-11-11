# typed: false
# frozen_string_literal: true

class ProjectCard
  module MigrationDependency
    extend ActiveSupport::Concern

    def to_memex_specification
      content_id = nil
      content_type = nil

      if content&.pull_request?
        content_type = "PullRequest"
        content_id = defined?(content.pull_request_id) ? content.pull_request_id : content.id
      elsif content
        content_type = content.class.name
        content_id = content.id
      end
      {
        "id": id,
        "content_id": content_id,
        "content_type": content_type,
        "draft_content": note,
        "column_values": [{
          "name": "Status",
          "value": column.name
        }],
        "is_archived": archived?
      }
    end
  end
end
