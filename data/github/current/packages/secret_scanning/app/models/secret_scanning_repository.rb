# typed: true
# frozen_string_literal: true

# This model is intentionally empty. The secret-scanning team is in the process
# of moving their database cluster into their own managed cluster. Long term,
# models such as this (and TokenScanResult) would likely be removed or gutted
# like this model.
#
# Currently however, they are still critical in test setup that requires seeding
# the database in order to record VCR cassettes.
class SecretScanningRepository < ApplicationRecord::TokenScanningService
end
