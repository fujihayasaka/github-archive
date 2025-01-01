# typed: true
# frozen_string_literal: true

# IntegrationInstallationRequest is bound to one or all repositories in the target organization.
# With this model, IntegrationInstallationRequest can have a has_many relationship to Repository.
class IntegrationInstallationRequestRepository < ApplicationRecord::Domain::Integrations

  belongs_to :integration_installation_request
  belongs_to :repository

  validates_presence_of :integration_installation_request, :repository

end
