# typed: true
# frozen_string_literal: true

class IntegrationListingFeature < ApplicationRecord::Domain::Integrations

  belongs_to :integration_feature
  belongs_to :integration_listing

end
