# typed: strict
# frozen_string_literal: true

#
# Viewscreen business logic, used to build the view logic in the creation of iframes.
module Viewscreen

  sig { returns(String) }
  def self.host_url
    if Rails.env.development?
      return "#{GitHub.scheme}://viewscreen.githubusercontent.localhost:9494"
    end

    if GitHub.employee_unicorn?
      return "#{GitHub.scheme}://viewscreen-lab.service.iad.github.net"
    end

    if GitHub.multi_tenant_enterprise?
      return "#{GitHub.scheme}://viewscreen.#{GitHub::CurrentTenant.get&.slug}.#{GitHub.host_name}"
    end

    if GitHub.enterprise? && !GitHub.subdomain_isolation?
      return "#{GitHub.scheme}://#{GitHub.user_content_host_name}#{GitHub.viewscreen_path_prefix}"
    end

    "#{GitHub.scheme}://viewscreen.#{GitHub.user_content_host_name}"
  end
end
