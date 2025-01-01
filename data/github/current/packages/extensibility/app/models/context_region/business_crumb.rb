# typed: strict
# frozen_string_literal: true

module ContextRegion
  class BusinessCrumb < Crumb
    sig { override.returns(String) }
    def label
      object.name || object.slug
    end

    sig { override.returns(Crumb) }
    def parent
      RootCrumb.new
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :enterprise_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end

    sig { override.returns(Site::Header::UnderlineNavComponent) }
    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(
        label: "User",
        tabs: Business::NavigationTabs.for(business: object, current_user: options[:current_user])
      )
    end

  end
end
