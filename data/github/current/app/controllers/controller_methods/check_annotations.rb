# typed: true
# frozen_string_literal: true

module ControllerMethods
  module CheckAnnotations
    def load_annotation_details(check_run:, after: nil)
      connection = Platform::ConnectionWrappers::Relation.new(
        check_run.annotations,
        first: CheckAnnotation::MAX_PER_REQUEST,
        after: after
      )
      annotations = connection.edge_nodes.sync
      page_info = connection.page_info

      {
        annotations_by_id: annotations.index_by(&:id),
        has_next_page: page_info.has_next_page,
        end_cursor: page_info.end_cursor
      }
    end
  end
end
