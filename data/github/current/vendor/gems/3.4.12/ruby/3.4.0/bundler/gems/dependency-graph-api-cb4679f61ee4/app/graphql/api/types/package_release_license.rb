module API
  module Types
    class PackageReleaseLicense < Types::BaseObject
      description "Count of a specific license"

      field :total_count, Integer, null: false
      field :license, String, null: false
    end
  end
end
