# typed: strict
# frozen_string_literal: true

module Repository::DeployKeysDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  # Deploy Keys
  sig { params(new_keys: T.untyped).void }
  def public_keys=(new_keys)
    new_keys = [new_keys].flatten.reject(&:blank?)

    public_keys.each do |key|
      public_keys.delete(key) unless new_keys.include? key.to_s
      new_keys.delete(key.to_s)
    end

    new_keys.each do |key|
      pk = PublicKey.new(repository: self, key: key.to_s)
      public_keys << pk
    end
  end

  sig { returns(T::Boolean) }
  def unverified_public_keys?
    public_keys.any? { |key| !key.verified? }
  end

  # Returns a tuple of whether deploy keys are disabled for this repository
  # and the name of the business or organization that has set the policy to disable deploy keys.
  # Returns nil for the name if deploy keys are not disabled.
  sig { returns([T::Boolean, T.nilable(String)]) }
  def deploy_keys_disabled_by_policy_with_policy_source
    # if the repo is owned by an emu user or we're running in a single business eng,
    # check the emu's business (or single business) policy
    # we specifically check this first, since this is sort of a "special case"
    # to check for - since "normal" user owned repos don't have a parent
    # that is applicable for the deploy key policy
    if !in_organization? && (emu_user_owned? || GitHub.single_business_environment?)
      biz = emu_user_owned? ? enterprise_managed_business : GitHub.global_business
      if biz&.deploy_key_policy_disabled?
        return true, biz.name
      end
      return false, nil
    end

    # if the repo is owned by a plain old user, no policy to check (because we know it's not an emu at this point)
    return false, nil if !in_organization?

    org = T.must(organization)

    # if it's enabled (regardless of whether it's inherited from the business or not), we can stop here
    if org.deploy_key_policy_enabled?
      return false, nil
    end

    # at this point we know it's disabled, so we are returning `true` for the first value
    # the second value is either the org or the business..
    # the business takes precedence over the org.. org.deploy_key_policy_inherited? returns
    # true if it's set on the business even if the org has it set to false
    if org.deploy_key_policy_inherited?
      return true, org.business&.name
    end

    # if it's not inherited from the business,
    # we should check if the org has the policy unset
    # unset == enabled, so we should return false here
    if org.deploy_key_policy_unset?
      return false, nil
    end

    [true, org.display_login]
  end
end
