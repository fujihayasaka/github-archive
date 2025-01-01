# typed: true
# frozen_string_literal: true

# Stores data about the canonical ownership of local (on-stamp) GitHub Apps and
# OAuth apps that have been synchronized from Dotcom to Proxima.
#
# Owners can be either User or Organization records.
class DotcomAppOwnerMetadata < ApplicationRecord::Domain::Integrations
  VALID_LOCAL_APP_TYPES = %w(Integration OauthApplication)

  belongs_to :local_app, polymorphic: true

  validates :local_app_type, inclusion: VALID_LOCAL_APP_TYPES

  def self.for_local_app(app)
    find_by(local_app: app)
  end
end
