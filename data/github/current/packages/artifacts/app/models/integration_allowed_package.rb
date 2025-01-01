# typed: true
# frozen_string_literal: true

class IntegrationAllowedPackage < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain strict_loading: false
  belongs_to :package, class_name: "Registry::Package"
  belongs_to :integration

  enum :access_type, { contents: 1, administration: 2, maintainer: 3 }
end
