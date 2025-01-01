# typed: true
# frozen_string_literal: true

module Site
  module BreadcrumbDependency
    def breadcrumbs
      @breadcrumbs ||= []
    end

    def add_breadcrumb(name, href)
      breadcrumbs << { name:, href: }
    end
  end
end
