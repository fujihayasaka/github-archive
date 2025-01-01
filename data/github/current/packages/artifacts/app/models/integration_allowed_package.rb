# typed: true
# frozen_string_literal: true

class IntegrationAllowedPackage < ApplicationRecord::Domain::Repositories
  belongs_to :repository, strict_loading: false
  belongs_to :package, class_name: "Registry::Package"
  belongs_to :integration

  enum :access_type, { contents: 1, administration: 2, maintainer: 3 }
end
