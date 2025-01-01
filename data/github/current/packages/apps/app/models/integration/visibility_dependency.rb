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
      Integration.where(public: true)
    end
  end

  # Public: Private Apps cannot be installed on anything other than the App's
  # owner.
  #
  # Returns a Boolean.
  def private?
    !public?
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
    if GitHub.flipper[:enterprise_owned_app_management].enabled?(owner)
      return false if self.enterprise_owned? && !connect_app?
    end

    # New records won't have listings or installations to fetch.
    return true if self.new_record?

    return false if integration_listing.present?

    installations_count = installations.count
    return true if installations_count == 0
    # Apps can only be installed once per target (user/organization/business
    # etc.), meaning that an App with more than one installation *must* be
    # installed on something other than their owner:
    return false if installations_count > 1

    installations.where(target: owner).exists?
  end

  def make_public
    update_attribute :public, true
  end

  def make_public!
    update!(public: true)
  end

  def make_private
    update(public: false)
  end

  def public_visibility?
    if GitHub.flipper[:enterprise_owned_app_management].enabled?(owner)
      # once we backfill, we can rely on the visibility column being public,
      # however for now, public visibility is the default and can't be trusted
      return if self.internal_visibility? || self.private_visibility?
    end

    self.public?
  end

  def private_visibility?
    if GitHub.flipper[:enterprise_owned_app_management].enabled?(owner)
      return if self.internal_visibility?
      return (self.visibility == "private_visibility") || self.private?
    end

    self.private?
  end

  # Dual write as we transition from :public to :visibility
  def public=(value)
    case value
    when true, "true"
      self.visibility = "public_visibility"
    when false, "false"
      self.visibility = "private_visibility"
    else
      raise ArgumentError, "Invalid public: #{value}"
    end
  end

  def visibility=(value)
    case value
    when "public_visibility"
      write_attribute(:public, true)
      write_attribute(:visibility, value)
    when "private_visibility"
      write_attribute(:public, false)
      write_attribute(:visibility, value)
    when "internal_visibility"
      write_attribute(:public, false)
      write_attribute(:visibility, value)
    else
      raise ArgumentError, "Invalid visibility: #{value}"
    end
  end

  private

  def non_emu_app_not_changing_privacy?
    !self.is_enterprised_managed?(owner) && !self.public_changed?
  end

  # Private: Ensure the integration can have the requested visibility.
  def validate_visibility
    if self.public_visibility?
      exception = self.enterprise_owned? && GitHub.flipper[:enterprise_owned_app_management].enabled?(owner)
      return unless exception

      errors.add(:visibility, "cannot be public")
    end

    if self.private_visibility?
      return if self.can_make_private?

      # for non-EMU owned integrations, only validate if
      # the app is being made private
      # https://github.com/github/ecosystem-apps/issues/5426
      return if non_emu_app_not_changing_privacy?

      errors.add(:public, "cannot be private")
    end

    if self.internal_visibility?
      return if self.enterprise_owned?
      errors.add(:visibility, "cannot have internal visibility")
    end
  end
end
