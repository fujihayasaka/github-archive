# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Elastomer
  class DeleteIndexFromClustersJob < ApplicationJob
    queue_as :index_high
    retry_on_dirty_exit

    def perform(index_name)
      # This workflow is only intended to be run on GitHub Enterprise
      GitHub.logger.with_named_tags("elastomer.index_name" => index_name) do
        if GitHub.enterprise?
          clusters = ::Elastomer.router.available_clusters
          clusters.each do |cluster|
            client = Elastomer.router.client(cluster)
            index = client.index(index_name)
            config = Elastomer.router.get_index_config(index_name)

            # Checks if index is elastomer managed and primary
            if config&.primary?
              GitHub.logger.info("Cannot delete primary index for elastomer managed index")

            elsif index.exists?
              index.delete
              GitHub.logger.info("Deleted index from cluster:", "elastomer.cluster" => cluster)
            else
              GitHub.logger.info("Search index does not exist in", "elastomer.cluster" => cluster)
            end
          end
        else
          GitHub.logger.info("Delete index from cluster job is not supported on GitHub.com.")
        end
      end
    end
  end
end
