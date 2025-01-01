# typed: true
# frozen_string_literal: true

class IntegrationListingLanguageName < ApplicationRecord::Domain::Integrations

  belongs_to :integration_listing
  belongs_to :language_name

end
