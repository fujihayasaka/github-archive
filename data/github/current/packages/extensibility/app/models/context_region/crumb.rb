# typed: true
# frozen_string_literal: true

module ContextRegion
  class Crumb
    attr_reader :object, :options

    def initialize(object = nil, options = {})
      @object = object
      @options = options
    end

    def label
      raise NotImplementedError
    end

    def dom_id
      return options[:dom_id] if options[:dom_id].present?
      # serialize a unique identifier for the crumb based on the label and the crumb's class name
      # in theory, this should be unique enough to be used as a dom id
      "#{self.class.name}-#{label.parameterize}".parameterize
    end

    # Override this with a symbol name of an octicon to decorate the crumb in the mobile context region dialog
    def prefix_octicon
      :link
    end

    sig { overridable.returns(Crumb) }
    def parent
      RootCrumb.new
    end

    def is_root?
      false
    end

    def octicon; end

    # Provide a symbol name of a Rails path helper (eg. :user_path)
    def path_name
      nil
    end

    # Provides any arguments to the path helper
    def path_args
      []
    end

    def link_data_attrs(link_opts = {})
      {}
    end

    # Use this to provide a path helper that can't be evaluated in view components (such as `home_url`)
    def path
      nil
    end

    # Use this to manually set a string to be used as the crumb's href attribute
    # This will take precedence over path_name and path when set
    def href
      nil
    end

    def has_path?
      path_name.present? || path.present?
    end

    def has_href?
      href.present?
    end

    def crumbs
      crumbs = []

      is_root = T.let(is_root?, T::Boolean)
      current_crumb = self

      while !is_root
        crumbs << current_crumb
        current_crumb = current_crumb.parent
        is_root = current_crumb.is_root?
      end

      crumbs.reverse
    end

    def label_classes; end

    sig { returns(T.nilable(Site::Header::UnderlineNavComponent)) }
    def header_navigation_component; end

    sig { returns(T.nilable(Site::Header::NavigationTabPopoverComponent)) }
    def header_navigation_popover_component; end
  end
end
