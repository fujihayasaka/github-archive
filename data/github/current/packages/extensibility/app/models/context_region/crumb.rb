# typed: strict
# frozen_string_literal: true

module ContextRegion
  class Crumb
    sig { returns(T.untyped) }
    attr_reader :object

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :options

    sig { params(object: T.untyped, options: T::Hash[T.untyped, T.untyped]).void }
    def initialize(object = nil, options = {})
      @object = object
      @options = options
    end

    sig { overridable.returns(String) }
    def label
      raise NotImplementedError
    end

    sig { returns(String) }
    def dom_id
      return options[:dom_id] if options[:dom_id].present?
      # serialize a unique identifier for the crumb based on the label and the crumb's class name
      # in theory, this should be unique enough to be used as a dom id
      "#{self.class.name}-#{label.parameterize}".parameterize
    end

    # Override this with a symbol name of an octicon to decorate the crumb in the mobile context region dialog
    sig { overridable.returns(Symbol) }
    def prefix_octicon
      :link
    end

    sig { overridable.returns(Crumb) }
    def parent
      RootCrumb.new
    end

    sig { overridable.returns(T::Boolean) }
    def is_root?
      false
    end

    sig { overridable.returns(T.nilable(Symbol)) }
    def octicon; end

    # Provide a symbol name of a Rails path helper (eg. :user_path)
    sig { overridable.returns(T.nilable(Symbol)) }
    def path_name
      nil
    end

    # Provides any arguments to the path helper
    sig { overridable.returns(T::Array[T.untyped]) }
    def path_args
      []
    end

    sig { params(link_opts: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def link_data_attrs(link_opts = {})
      {}
    end

    # Use this to provide a path helper that can't be evaluated in view components (such as `home_url`)
    sig { overridable.returns(T.nilable(String)) }
    def path
      nil
    end

    # Use this to manually set a string to be used as the crumb's href attribute
    # This will take precedence over path_name and path when set
    sig { overridable.returns(T.nilable(String)) }
    def href
      nil
    end

    sig { returns(T::Boolean) }
    def has_path?
      path_name.present? || path.present?
    end

    sig { returns(T::Boolean) }
    def has_href?
      href.present?
    end

    sig { returns(T::Array[Crumb]) }
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

    # Returns a clean type identifier for the crumb (e.g., "team", "repository", "root")
    sig { returns(Symbol) }
    def crumb_type
      class_name = self.class.name&.split("::")&.last
      return :basic unless class_name

      class_name.gsub(/Crumb\z/, "").underscore.to_sym
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        crumb_type: crumb_type,
        label: label,
        is_root: is_root?,
        octicon: octicon,
        path: path,
        href: href,
        sub_navigation: sub_navigation,
      }.compact
    end

    sig { overridable.returns(T::Array[T.untyped]) }
    def sub_navigation
      []
    end

    sig { overridable.returns(T.nilable(String)) }
    def label_classes; end

    sig { overridable.returns(T.nilable(T.any(Site::Header::UnderlineNavComponent, Repositories::UnderlineNavComponent))) }
    def header_navigation_component; end

    sig { returns(T.nilable(Site::Header::NavigationTabPopoverComponent)) }
    def header_navigation_popover_component; end
  end
end
