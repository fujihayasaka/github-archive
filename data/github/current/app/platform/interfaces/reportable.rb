# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Reportable
      include Platform::Interfaces::Base
      description "Entities that can be reported."

      visibility :internal

      url_fields description: "The HTTP URL for this object", visibility: :internal do |object|
        object.async_path_uri
      end

      field :viewer_can_report, Boolean, visibility: :internal, description: "Can the viewer report this object", null: false

      def viewer_can_report
        @object.async_viewer_can_report?(@context[:viewer])
      end

      field :viewer_can_report_to_maintainer, Boolean, visibility: :internal, description: "Can the viewer report this object to the maintainer", null: false

      def viewer_can_report_to_maintainer
        @object.async_viewer_can_report_to_maintainer?(@context[:viewer])
      end

      field :viewer_relationship, Enums::CommentAuthorAssociation, visibility: :internal, description: "Indicates the relationship the viewer has with this repository.", null: false

      def viewer_relationship
        @object.async_viewer_relationship(@context[:viewer])
      end
    end
  end
end
