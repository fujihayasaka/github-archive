# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the models with the index.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offest into the repositories table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairRegistryPackagesIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "registry_package",
    fields:      %w[updated_at],
    include:     [:owner],
    limit:       100,
    model_class: Registry::Package,
    reject:      %w[migrated?]
end
