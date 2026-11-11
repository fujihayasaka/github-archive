module Models
  class Dependency < Base
    belongs_to :rubygem

    def package_name
      rubygem&.name || unresolved_name
    end

    def development?
      scope == "development".freeze
    end
  end
end
