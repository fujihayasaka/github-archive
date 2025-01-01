# typed: true
# frozen_string_literal: true

module GitAuth
  class SSHLoginParser
    # parses the given ssh_login value when applicable
    #
    # in multi-tenant enterprise, the ssh_login is in the form of
    # `<tenant_slug>` or `<tenant_slug>_<org_id>`
    # if `<tenant_slug>`, the return should be [nil, <tenant_slug>]
    # if `<tenant_slug>_<org_id>`, the return should be [<org_id>, <tenant_slug>]
    # note - a tenant slug can never have an underscore (see Business::SLUG_REGEX)
    #
    # when not in multi-tenent enterprise, the ssh_login is in the form of
    # `git` or `org-<org_id>`
    # if `git`, the return should be [nil, nil]
    # if `org-<org_id>`, the return should be [<org_id>, nil]
    def self.parse(ssh_login)
      return [nil, nil] if ssh_login.nil?

      if GitHub.multi_tenant_enterprise?
        if match = ssh_login.match(/\A(.+)_(\d+)\z/)
          tenant_slug = match[1]
          org_id = match[2].to_i
        else
          tenant_slug = ssh_login
          org_id = nil
        end
        [org_id, tenant_slug]
      else
        org_id = if match = ssh_login.match(/\Aorg-(\d+)\z/)
          match[1].to_i
        end
        [org_id, nil]
      end
    end
  end
end
