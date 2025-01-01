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

    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(
        label: "User",
        tabs: Business::NavigationTabs.for(business: object, current_user: options[:current_user])
      )
    end

  end
end
