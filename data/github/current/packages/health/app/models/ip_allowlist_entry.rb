# typed: true
# frozen_string_literal: true

class IpAllowlistEntry < ApplicationRecord::Collab
  include GitHub::Validations
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  belongs_to :owner, polymorphic: true

  # actor_ip does not map to a database column. It should be set with a String
  # value representing the actor's IP address when creating/updating/destroying
  # an IpAllowlistEntry if you want to prevent the actor being locked out of the
  # account that owns the entry.
  #
  # For example:
  #
  # entry = owner.ip_allowlist_entries.new(entry_params)
  # entry.actor_ip = request.remote_ip
  # if entry.save ...
  attr_accessor :actor_ip

  validates :owner, presence: true
  validate :valid_owner_type
  validate :valid_plan_for_owner

  validates :name, length: { maximum: 255 }, allow_blank: true, unicode3: true
  validates :allow_list_value, presence: true
  validate :valid_allow_list_value
  validate :prevent_actor_being_locked_out
  before_destroy -> do
    T.bind(self, IpAllowlistEntry)
    prevent_actor_being_locked_out(context: :destroy)
  end, prepend: true

  before_save :set_range_values
  after_create_commit :instrument_create
  after_update_commit :instrument_update
  after_destroy_commit :instrument_destroy

  def platform_type_name
    "IpAllowListEntry"
  end

  # Scope that returns the IP allow list entries owned by object or by
  # the owners of object.
  #
  # object - The object for which the usable IP allow list entries should be returned.
  #
  # Returns ActiveRecord::Relation.
  scope :usable_for, ->(object) {
    case object
    when Organization
      # Organizations only inherit the IP allow list entries from an owning
      # enterprise account when an IP allow list is *enabled* on the owning
      # enterprise account.
      if object.business&.ip_allowlist_enabled?
        usable_for(object.business).or(where(
          owner_type: object.class.base_class.name,
          owner_id: object.id,
        ))
      else
        where(
          owner_type: object.class.base_class.name,
          owner_id: object.id,
        )
      end
    when Business
      where(
        owner_type: object.class.base_class.name,
        owner_id: object.id,
      )
    when Integration
      where(
        owner_type: object.class.base_class.name,
        owner_id: object.id,
      )
    when IntegrationInstallation
      where(
        owner_type: object.integration&.class&.base_class.name,
        owner_id: object.integration&.id,
      )
    when Array
      where(
        owner_type: Integration.base_class.name,
        owner_id: object,
      )
    else
      where("1=0")
    end
  }

  scope :installed_for, ->(object) {
    case object
    when Organization
      usable_for(IntegrationInstallation.where(target_id: object.id, target_type: "User").map(&:integration_id))
    when Business
      usable_for(IntegrationInstallation.where(target_id: object.id, target_type: "Business").map(&:integration_id))
    else
      where("1=0")
    end
  }

  # Scope that returns only IP allow list entries that are active.
  #
  # Returns ActiveRecord::Relation.
  scope :active, -> { where(active: true) }

  # Scope that returns only IP allow list entries that match the given IP
  # address.
  #
  # ip - String representing a single IPv4 or IPv6 address.
  #
  # Returns ActiveRecord::Relation.
  scope :matching_ip, ->(ip) {
    # Values that include a trailing network mask or zone ID cause query warnings when passed to INET6_ATON
    # See https://dev.mysql.com/doc/refman/5.7/en/miscellaneous-functions.html#function_inet6-aton
    return IpAllowlistEntry.none if ip.to_s.match(%r[\/|\%])

    # Values that are not a valid address cause query warnings when passed to INET6_ATON
    # See https://dev.mysql.com/doc/refman/5.7/en/miscellaneous-functions.html#function_inet6-aton
    begin
      ip = IPAddr.new(ip).native.to_s
    rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      return IpAllowlistEntry.none
    end

    where <<-SQL, ip: ip
      INET6_ATON(:ip)
      BETWEEN `ip_allowlist_entries`.`range_from`
      AND     `ip_allowlist_entries`.`range_to`
    SQL
  }

  # Scope that returns only entries where `allow_list_value` or `name` match
  # the given query.
  #
  # Should only be used for filtering existing well scoped queries. For example,
  # filtering entries already belonging to a specific owner.
  #
  # query - String containing the query.
  #
  # Returns ActiveRecord::Relation.
  scope :for_query, ->(query) {
    safe_query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    return scoped unless safe_query.present?

    where <<-SQL, query: "%#{safe_query}%"
      ip_allowlist_entries.allow_list_value LIKE :query
      OR ip_allowlist_entries.name LIKE :query
    SQL
  }

  # Public: Returns a String containing the name and type of the owner for use
  # in copy that refers to the owner owning/managing the IP allow list entry.
  #
  # Returns String.
  def owner_name_and_type
    if owner_type == "Business"
      "#{owner.name} enterprise"
    elsif owner_type == "Integration"
      "#{owner.name} GitHub App"
    else
      "#{owner.safe_profile_name} organization"
    end
  end

  # Public: Returns a Boolean indicating whether this IP allow list entry
  # includes a specific IP address?
  #
  # ip - A String representing a single IP address.
  #
  # Returns Boolean.
  def includes?(ip)
    block = begin
      IPAddr.new(allow_list_value)
    rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      return false
    end

    included = begin
      block.include?(IPAddr.new(ip).native.to_s)
    rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      return false
    end

    included
  end

  # Public: Is a potential IP allow list entry owner eligible for the IP
  # allow list feature?
  #
  # IP allow lists are available to enterprise accounts and organization
  # accounts on the Enterprise plan (internally `business_plus`).
  #
  # owner - A potential owner of an IP allow list entry. Currently expected to be
  # a Business, Organization, or Integration.
  #
  # Returns Boolean.
  def self.eligible_for_ip_allowlist?(owner)
    owner.is_a?(::Business) ||
    (owner.is_a?(::Organization) && owner.plan_supports?(:ip_allowlist)) ||
    owner.is_a?(::Integration)
  end

  # Public: Is the owner of this entry eligible for the IP allow list feature?
  #
  # Returns Boolean.
  def owner_eligible_for_ip_allowlist?
    self.class.eligible_for_ip_allowlist?(owner)
  end

  def event_prefix
    :ip_allow_list_entry
  end

  def event_context(prefix: event_prefix)
    {
      prefix => allow_list_value,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    {}.tap do |payload|
      payload[:ip_allow_list_entry] = self
      payload[:ip_allow_list_entry_name] = name
      payload[:active] = active?
      payload[owner.event_prefix] = owner
      payload[owner.owner.event_prefix] = owner.owner if owner.is_a?(::Integration)
    end
  end

  # Public: Is the IP address included in the Array of IpAllowlistEntries?
  #
  # ip - A String representing an IP address.
  # entries - An Array of IpAllowlistEntry objects.
  #
  # Returns Boolean.
  def self.ip_included_in_entries?(ip:, entries:)
    return false if ip.blank? || entries.blank?

    entries.each do |entry|
      return true if entry.includes?(ip)
    end

    false
  end

  private

  # Check that the owner is a Business, Organization or Integration.
  # Don't use the Rails `inclusion` validation because `owner_type` is actually
  # "User" for orgs.
  def valid_owner_type
    return if [Business, Organization, Integration].include?(owner.class)
    errors.add(:owner, "must be an enterprise account, organization, or GitHub App")
  end

  # Check that the owner has an eligible plan for IP allow list.
  def valid_plan_for_owner
    unless owner_eligible_for_ip_allowlist?
      errors.add(:owner, "doesn't have an eligible plan for an IP allow list")
    end
  end

  # Check that allow_list_value is valid. It should be a single IPv4/IPv6
  # address (Examples: "192.168.103.201","2001:db8:0:ffff:ffff:ffff:ffff:ffff")
  # or a range of IPv4/IPv6 addresses in CIDR notation (Examples:
  # "192.168.100.0/22", "2001:db8::/48").
  def valid_allow_list_value
    begin
      IPAddr.new(self.allow_list_value)
    rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      errors.add(:allow_list_value, "must be a valid IP address or range of addresses in CIDR notation")
    end
  end

  # Set range_from and range_to to the network byte ordered string form of the
  # first and last IP addresses in the range.
  def set_range_values
    ip_addr = IPAddr.new(self.allow_list_value)
    range = ip_addr.to_range
    self.range_from = range.first.hton
    self.range_to = range.last.hton
  end

  def instrument_create
    instrument :create
    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("ip_allow_list_entry.create", {
      entry: self, actor: actor
    })
  end

  def instrument_update
    instrument :update
    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("ip_allow_list_entry.update", {
      entry: self, actor: actor
    })
  end

  def instrument_destroy
    instrument :destroy
    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("ip_allow_list_entry.destroy", {
      entry: self, actor: actor
    })
  end

  # Check that creating/updating/destroying the entry will not lock the actor
  # out based on the presence of actor_ip.
  #
  # context - Optional Symbol indicating the context. Currently only accepted
  #   as `:destroy` to allow this method to be shared between `validates` and
  #   `before_destroy`.
  #
  # Returns nothing.
  def prevent_actor_being_locked_out(context: nil)
    # GitHub Apps with IP allow lists cannot be locked out based on the IP allow list entries.
    return if owner.is_a?(Integration)

    # Skip if `actor_ip` is not provided, if the IP allow list is not enabled,
    # or if there are any existing validation errors present.
    return unless actor_ip.present?
    return unless owner&.ip_allowlist_enabled?
    return if errors.any?

    # Set up the active entries that would result from this
    # create/update/destroy.
    active_entries = IpAllowlistEntry.usable_for(owner).active.to_a
    if new_record? && active?
      active_entries << self
    elsif persisted?
      active_entries.delete_if { |entry| entry.id == self.id }
      if active? && context != :destroy
        active_entries << self
      end
    end

    return if IpAllowlistEntry.ip_included_in_entries? \
      ip: actor_ip, entries: active_entries

    errors.add(:base, "This change would prevent you from accessing the account from your current IP address")

    throw :abort
  end
end
