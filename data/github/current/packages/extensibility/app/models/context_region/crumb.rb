# typed: true
# frozen_string_literal: true

module ContextRegion
  class Crumb
    extend T::Sig
    attr_reader :object, :options

    def initialize(object = nil, options = {})
      @object = object
      @options = options
    end

    def label
      raise NotImplementedError
    end

    # Override this with a symbol name of an octicon to decorate the crumb in the mobile context region dialog
    def compact_octicon
      :link
    end

    sig { returns(ContextRegion::RootCrumb) }
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

    def has_path?
      path_name.present? || path.present?
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
    def header_navigation_component; end
  end
end
