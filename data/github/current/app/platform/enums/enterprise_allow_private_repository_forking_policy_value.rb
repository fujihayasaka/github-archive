# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseAllowPrivateRepositoryForkingPolicyValue < Platform::Enums::Base
      docs_category :enterprise_admin

      description "The possible values for the enterprise allow private repository forking policy value."

      value "ENTERPRISE_ORGANIZATIONS", "Members can fork a repository to an organization within this enterprise."
      value "SAME_ORGANIZATION", "Members can fork a repository only within the same organization (intra-org)."
      value "SAME_ORGANIZATION_USER_ACCOUNTS", "Members can fork a repository to their user account or within the same organization."
      value "ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS", "Members can fork a repository to their enterprise-managed user account or an organization inside this enterprise."
      value "USER_ACCOUNTS", "Members can fork a repository to their user account."
      value "EVERYWHERE", "Members can fork a repository to their user account or an organization, either inside or outside of this enterprise. Internal repositories can only be forked inside of this enterprise."
    end
  end
end
