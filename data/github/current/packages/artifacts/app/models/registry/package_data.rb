# typed: true
# frozen_string_literal: true

module Registry
  class PackageData
    attr_accessor :package_type
    attr_accessor :total_pkgs_published_count
    attr_accessor :distinct_owners_count
    attr_accessor :distinct_owners_to_enumerate
    attr_accessor :name
    attr_accessor :pretty_name

    def initialize(
        package_type,
        total_pkgs_published_count,
        distinct_owners_count,
        distinct_owners_to_enumerate,
        name,
        pretty_name
      )
      @package_type = package_type
      @total_pkgs_published_count = total_pkgs_published_count
      @distinct_owners_count = distinct_owners_count
      @distinct_owners_to_enumerate = distinct_owners_to_enumerate
      @name = name
      @pretty_name = pretty_name
    end
  end
end
