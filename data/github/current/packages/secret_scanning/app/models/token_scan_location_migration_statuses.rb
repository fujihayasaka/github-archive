# typed: true
# frozen_string_literal: true

# This model is intentionally empty. The secret-scanning team is in the process
# of moving their database cluster into their own managed cluster.
#
# Currently however, they are still critical in test setup that requires seeding
# the database in order to record VCR cassettes, or transitions.
class TokenScanLocationMigrationStatuses < ApplicationRecord::TokenScanningService
end
