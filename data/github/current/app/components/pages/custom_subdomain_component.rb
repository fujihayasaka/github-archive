# typed: true
# frozen_string_literal: true

module Pages
  class CustomSubdomainComponent < ApplicationComponent
    attr_reader :repository

    def initialize(repository:)
      @repository = repository
    end

    memoize def page
      @repository.page
    end

    def default_subdomain
      return unless page && page.subdomain
      page.display_subdomain
    end

    def show_update_domain_toast?
      return false unless GitHub.multi_tenant_enterprise?
      return false unless page
      return true if PageUpdate.where(page_id: page.id, event: :update_subdomain_event).exists?
      false
    end
  end
end
