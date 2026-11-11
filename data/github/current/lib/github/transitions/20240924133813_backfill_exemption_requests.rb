# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillExemptionRequests < Base

      class ExemptionRequests < ApplicationRecord::Domain::Repositories
        self.table_name = :exemption_requests
      end

      sig { override.void }
      def perform
        # There are only 2800 records in this table. We can process them all at once
        repo_ids = ExemptionRequests.where(owner_id: 0).where("repository_id IS NOT NULL").distinct.pluck(:repository_id)
        repos = Repository.where(id: repo_ids)

        repos.each do |repo|
          # NOTE: repo.owner.business_id <> repo.owner.business.id
          business_id = repo&.owner&.business&.id
          owner_id = repo&.owner_id || 0

          if dry_run?
            count = ExemptionRequests.where(repository_id: repo.id, owner_id: 0).size
            log("Did not update #{count} records for repo #{repo.id} owner #{repo.owner_id} business #{business_id}")
          else
            write_to(model_class: ApplicationRecord::Domain::Repositories) do
              rows = ExemptionRequests.where(repository_id: repo.id, owner_id: 0).update_all(owner_id: owner_id, business_id: business_id)
              log("Updated #{rows} records for repo #{repo.id} owner #{owner_id} business #{business_id}")
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillExemptionRequests.new(args).run
end
