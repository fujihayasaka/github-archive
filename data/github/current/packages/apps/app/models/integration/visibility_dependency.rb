# typed: true
# frozen_string_literal: true

module Integration::VisibilityDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Integration }

  included do
    # Public: Integer state of the application's visibility for installation
    #
    # column :visibility
    #   :public   - Is installable by anyone
    #   :private  - Is only installable for the owner
    #   :internal - Is only installable for the owning enterprise's orgs
    T.bind(self, T.class_of(Integration))
    self.enum :visibility, { public_visibility: 0, private_visibility: 1, internal_visibility: 2 }

    # Exclude Integrations that are internal/private, returning only public integrations.
    # Beware, this is overriding the built-in `public` method.
    # Example of what can go wrong: https://github.com/github/dependency-graph-api/pull/2557
    def self.public
      Integration.where(visibility: "public_visibility")
    end
  end

  # Public: Can this App be marked as "private"? Prevents the App being
  # installed by anybody but the App's owner/owning organization.
  #
  # - Apps not installed anywhere can be private
  # - Apps installed only on their owner can be private
  # - Apps listed in the marketplace can't be private
  # - Apps installed on anything other than their owner can't be private
  # - Apps owned by an EMU can't be private
  # - Apps owned by an enterprise can't be private (for now, except for connect)
  #
  # Returns a Boolean.
  def can_make_private?
    # EMU owned Apps can't be made private because Apps are not allowed to be
    # installed on EMUs.
    return false if owner.respond_to?(:is_enterprise_managed?) && owner.is_enterprise_managed?
    return false if self.enterprise_owned? && !connect_app?

    # New records won't have listings or installations to fetch.
    return true if self.new_record?

    return false if integration_listing.present?

    installations_count = limited_installations_count
    return true if installations_count == 0
    # Apps can only be installed once per target (user/organization/business
    # etc.), meaning that an App with more than one installation *must* be
    # installed on something other than their owner:
    return false if installations_count > 1

    installations.where(target: owner).exists?
  end

  def can_make_public?
    return false unless self.private_visibility?

    case self.owner
    when Organization
      true
    when User
      !self.owner.is_enterprise_managed?
    when Business
      false # Business Apps can be internal only for now
    else
      false # Should never happen
    end
  end

  def make_public
    update_attribute :visibility, "public_visibility"
  end

  def make_public!
    update!(visibility: "public_visibility")
  end

  def make_private
    update(visibility: "private_visibility")
  end

  # Dual write as we transition from :public to :visibility
  def public=(value)
    # TODO: Raise in dev/test and instrument in production until we're able to
    # drop the column. This is intended to be temporary.
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    if Rails.env.production?
      GitHub.dogstats.increment("integration.deprecated_public_setter")
    else
      # This DB transition gets a pass for now because it's responsible for backfilling the visibility column.
      unless caller.any?(/20240826200921_backfill_integration_visibility_test.rb/)
        raise NotImplementedError, "`integrations.public` is no longer in use. See `integrations.visibility`."
      end
    end

    case value
    when true, "true"
      self.visibility = "public_visibility"
    when false, "false"
      self.visibility = "private_visibility"
    else
      raise ArgumentError, "Invalid public: #{value}"
    end
  end

  # TODO: Remove this once we've consolidated all of the call-sites that pass
  # values to update public/private visibility of apps. At this point we can
  # rely on Rails' built in enum methods.
  #
  # https://github.com/github/ecosystem-apps/issues/6122
  def visibility=(value)
    case value
    when "public_visibility", "public", :public_visibility, :public
      write_attribute(:public, true)
      write_attribute(:visibility, value)
    when "private_visibility", "private", :private_visibility, :private
      write_attribute(:public, false)
      write_attribute(:visibility, value)
    when "internal_visibility", "internal", :internal_visibility, :internal
      write_attribute(:public, false)
      write_attribute(:visibility, value)
    else
      raise ArgumentError, "Invalid visibility: #{value}"
    end
  end

  private

  MULTIPLE_INSTALLATIONS_ERROR_MESSAGE = "A private app cannot have multiple installations. Please uninstall from all but one account to proceed.".freeze

  # Limit the number of installations counted to two, as we only need to know
  # if there is more than one.
  def limited_installations_count
    self.installations.limit(2).count
  end

  def non_emu_app_not_becoming_private?
    !self.is_enterprised_managed?(owner) && !(self.visibility_changed? && self.private_visibility?)
  end

  # Private: Ensure the integration can have the requested visibility.
  def validate_visibility
    if self.public_visibility?
      exception = self.enterprise_owned?
      return unless exception

      errors.add(:visibility, "cannot be public")
    end

    if self.private_visibility?
      return if self.can_make_private?

      # for non-EMU owned integrations, only validate if
      # the app is being made private
      # https://github.com/github/ecosystem-apps/issues/5426
      return if non_emu_app_not_becoming_private?

      if limited_installations_count > 1
        errors.add(:base, MULTIPLE_INSTALLATIONS_ERROR_MESSAGE)
      else
        errors.add(:public, "cannot be private")
      end
    end

    if self.internal_visibility?
      return if self.enterprise_owned?
      errors.add(:visibility, "cannot have internal visibility")
    end
  end
end
