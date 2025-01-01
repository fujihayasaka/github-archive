# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SignupsDeliveryJob < ApplicationDeliveryJob
  queue_as :signup_emails
end
