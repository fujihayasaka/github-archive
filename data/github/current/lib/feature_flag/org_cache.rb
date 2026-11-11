# typed: true
# frozen_string_literal: true

module FeatureFlag
  # Internal: Loads and memoizes the Shopify org.
  #
  # Returns an org or false if it doesn't exist.
  def shopify_org
    org_cache["shopify"]
  end

  # Internal: Checks to see if the User has access to the Organization.
  #
  # org_name - The symbol name of the org.
  # user     - The User.
  #
  # Returns a Boolean.
  def user_org_access?(org_name, user)
    org = org_cache[org_name.to_s]

    return false unless org

    ActiveRecord::Base.connected_to(role: :reading) do
      Ability.unscoped do
        GitHub.dogstats.distribution_time("feature_flags.orgs.member_check_latency", tags: ["org_name:#{org_name}"]) do
          org.member?(user)
        end
      end
    end
  end

  # Cached org-name to Organization object mapping.
  #
  # Accessing this Hash will lookup and cache organization.
  #
  # Returns a Hash.
  def org_cache
    @org_cache ||= Hash.new do |hash, org_name|
      hash[org_name] = begin
        if GitHub.multi_tenant_enterprise?
          false
        else
          ActiveRecord::Base.connected_to(role: :reading) do
            Organization.unscoped do
              GitHub.dogstats.distribution_time("feature_flags.groups.org_cache_latency", tags: ["org_name:#{org_name}"]) do
                Organization.find_by_login(org_name) || false
              end
            end
          end
        end
      end
    end
  end

  extend self
end
