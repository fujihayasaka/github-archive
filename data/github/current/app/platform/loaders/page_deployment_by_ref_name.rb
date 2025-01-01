# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class PageDeploymentByRefName < Platform::Loader
      def self.load(page_id, ref_name)
        self.for.load([page_id, ref_name])
      end

      def self.load_all(page_id, ref_names)
        loader = self.for
        Promise.all(ref_names.map { |ref_name| loader.load(page_id, ref_name) })
      end

      # Fetch the Page::Deployment records corresponding to a list of [page_id, ref_name] tuples.
      #
      # Relies on a UNIQUE index on the page_deployments table which enforces the uniqueness of
      # the [page_id, ref_name] tuple in the DB so we only ever get 1 record back for each tuple.
      #
      # Returns a Hash where the keys are [page_id, ref_name] tuples and the values are corresponding
      # Page::Deployment records.
      def fetch(page_ids_and_ref_names)
        conditions = page_ids_and_ref_names.map do |_, _|
          "(`page_deployments`.`page_id` = ? AND `page_deployments`.`ref_name` = ?)"
        end.join(" OR ")

        Page::Deployment
          .where(conditions, *page_ids_and_ref_names.flatten)
          .index_by { |d| [d.page_id, d.ref_name] }
      end
    end
  end
end
