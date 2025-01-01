# typed: true
# frozen_string_literal: true

module ContextRegion
  class BusinessCrumb < Crumb
    def label
      object.name || object.slug
    end

    def parent
      RootCrumb.new
    end

    def path_name
      :enterprise_path
    end

    def path_args
      [object]
    end
  end
end
