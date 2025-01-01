# typed: true
# frozen_string_literal: true

class Registry::PackageStorageUtilizations < ApplicationRecord::Domain::Packages
  belongs_to :owner, class_name: "User"
end
