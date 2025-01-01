# typed: true
# frozen_string_literal: true

module Notebook

  sig { returns(String) }
  def self.host_url
    if Rails.env.development?
      return "#{GitHub.scheme}://notebooks.githubusercontent.localhost:#{self.local_port}"
    end

    if GitHub.employee_unicorn?
      return "#{GitHub.scheme}://notebooks-lab.service.iad.github.net"
    end

    if GitHub.multi_tenant_enterprise?
      return "#{GitHub.scheme}://notebooks.#{GitHub::CurrentTenant.get&.slug}.#{GitHub.host_name}"
    end

    if GitHub.enterprise? && !GitHub.subdomain_isolation?
      return "#{GitHub.scheme}://#{GitHub.user_content_host_name}#{GitHub.notebooks_path_prefix}"
    end

    "#{GitHub.scheme}://notebooks.#{GitHub.user_content_host_name}"
  end

  sig { returns(String) }
  def self.local_port
    "8888"
  end
end
