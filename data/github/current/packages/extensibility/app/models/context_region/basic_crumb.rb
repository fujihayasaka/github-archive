# typed: true
# frozen_string_literal: true

module ContextRegion
  class BasicCrumb < Crumb
    def label
      options[:label]
    end

    def path_name
      options[:path_name]
    end

    def path_args
      options[:path_args]
    end

    def path
      options[:path]
    end

    def parent
      options[:parent] || super
    end
  end
end
