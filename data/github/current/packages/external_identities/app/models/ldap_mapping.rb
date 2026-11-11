# typed: false
# frozen_string_literal: true

require "digest/sha1"

class LdapMapping < ApplicationRecord::Domain::Users
  include GitHub::Validations
  validates_presence_of :dn
  validates_uniqueness_of :dn_hash, if: :user_mapping?, case_sensitive: false, unicode3: true

  belongs_to :subject, polymorphic: true

  before_validation :hash_dn!, if: [:dn?, :dn_changed?]

  # values in ldap_group_members are stored as hashes
  # rubocop:todo Rails/InverseOf
  has_many :ldap_group_members, primary_key: :dn_hash, foreign_key: :group_dn, dependent: :delete_all
  # rubocop:enable Rails/InverseOf

  # find an LdapMapping by DN, using the indexed `dn_hash` field to locate
  scope :by_dn, lambda { |dn| where(dn_hash: hash_dn(dn)) }

  enum :sync_status, {
    synced: 0, # synced
    error: 1, # error syncing
    syncing: 2, # currently syncing
    queued: 3, # sync queued
    gone: 4, # sync target missing
  }

  # Raised from the `sync` block to indicate the LDAP entry is missing.
  class MissingEntryError < StandardError; end

  # Public: Returns the Net::LDAP::Entry the subject maps to.
  def entry
    return @entry if defined?(@entry)
    @entry = load_entry
  end

  # Public: Returns a GitHub::Ldap::Domain instance.
  def domain
    GitHub.auth.strategy.domain(dn)
  end

  # Public: Returns the LDAP User's profile String name (or nil).
  def name
    return @name if defined?(@name)
    @name = GitHub.auth.profile_info(entry, :name).first
  end

  # Public: Returns the LDAP User's profile String login (or nil).
  def login
    return @login if defined?(@login)
    @login = GitHub.auth.profile_info(entry, :uid).first
  end

  def group_name
    @group_name ||= entry[:cn].first
  end

  # Public: Track sync progress as local state.
  #
  # The `add_runtime` keyword argument increases the recorded `last_sync_ms`
  # field by the Integer number of milliseconds passed in. The default is zero.
  # Use this argument to factor in runtime of work that happens outside of the
  # `sync` block, such as LDAP searches.
  #
  # In order to trigger logging out LDAP activity the event_payload should
  # contain an :ldap_fields_changed key whose value, if an Array with
  # elements, will trigger an audit log entry along with the list of fields.
  #
  # Raise `LdapMapping::MissingEntryError` in the `sync` block to signal that
  # the sync target is missing. Sets the sync status to `gone` and finishes.
  #
  # Returns nothing.
  def sync(add_runtime: 0, &block)
    start  = Time.now
    finish = nil
    status = :syncing
    event_payload = { dn: dn }
    update_column :sync_status, self.class.sync_statuses[status]

    block.call(event_payload)

    if should_instrument_ldap_sync?(event_payload)
      instrument :ldap_sync, event_payload
    end

    finish = Time.now
    status = :synced
  rescue MissingEntryError
    finish = Time.now
    status = :gone
    instrument :ldap_sync_error, event_payload.merge(error: :missing_entry)
  rescue Exception => error # rubocop:todo Lint/RescueException
    finish = Time.now
    status = :error
    instrument :ldap_sync_error, event_payload.merge(error: error)
    raise
  ensure
    unless destroyed?
      duration = (finish - start) * 1000 # milliseconds
      first_sync = !last_sync_at?
      update \
        sync_status: status,
        last_sync_at: finish,
        last_sync_ms: duration + add_runtime
      subject.after_first_sync if first_sync
    end
  end

  # Public: Returns true if the String dn is a member of the group cache for
  # this team.
  def group_cache_member?(dn)
    return if user_mapping?

    ldap_group_members.where(member_dn: self.class.hash_dn(dn)).exists? ||
    # A fallback query to query membership table without a hash to preserve backwards compatibility
    ldap_group_members.where(member_dn: dn).exists?
  end

  # Public: Set the group cache for this team to the given list of DNs.
  #
  # dns: an Array of String DNs.
  #
  # Returns nothing.
  def group_cache_set_members(dns)
    return if user_mapping?

    # clear existing members
    transaction do
      LdapGroupMember.where(group_dn: dn_hash).delete_all
      dns.each { |dn| group_cache_create_membership(dn) }
    end
  end

  # Public: Sets the single value in the group cache for the member.
  #
  # dn: an single member dn entry
  #
  # Returns LdapGroupMember.
  def group_cache_create_membership(dn)
    ldap_group_members.create(member_dn: self.class.hash_dn(dn))
  end

  def team_mapping?
    self.subject_type == "Team"
  end

  # Public: Returns a computed SHA1 hash String of the lower-cased DN.
  def self.hash_dn(dn)
    Digest::SHA1.hexdigest(canonicalize(dn)) # rubocop:disable GitHub/InsecureHashAlgorithm
  end

  # used to encode escaped commas (simplifies stripping whitespace between RDNs)
  SPECIAL_CHAR_PATTERN = /(?<=\\),/
  SPECIAL_CHAR_REPLACE = { "," => "2c" }

  # used to strip whitespace between RDNs (following unencoded commas)
  IGNORED_WHITESPACE_PATTERN = /,\s+/
  IGNORED_WHITESPACE_REPLACE = ","

  # Public: given one DN argument, returns its canonical representation
  # This helps identifying a DN that can have several representations.
  # See https://www.ldap.com/ldap-dns-and-rdns for more information
  def self.canonicalize(dn)
    dn.downcase.
      gsub(SPECIAL_CHAR_PATTERN, SPECIAL_CHAR_REPLACE).
      gsub(IGNORED_WHITESPACE_PATTERN, IGNORED_WHITESPACE_REPLACE)
  end

  private

  # Internal: Returns a GitHub::Ldap::Domain instance or false.
  def load_entry
    domain.bind
  end

  def user_mapping?
    self.subject_type == "User"
  end

  include Instrumentation::Model

  # Internal: Return the Symbol event prefix for instrumentation.
  def event_prefix
    case subject_type
    when "User" then :user
    when "Team" then :team
    end
  end

  # Internal: Return the event payload Hash for instrumentation.
  def event_payload
    subject.event_payload.merge(dn: dn)
  end

  # Internal: Update the `dn_hash` field with the hashed DN.
  def hash_dn!
    self.dn_hash = self.class.hash_dn(dn)
  end

  # Internal: determines if we should sync the LDAP activity based on contents
  # of block_call_value
  def should_instrument_ldap_sync?(event_payload)
    # all LDAP logging is enabled for debug purposes
    return true if GitHub::LDAP.debug_logging_enabled?
    event_payload.is_a?(Hash) && Array(event_payload[:ldap_fields_changed]).any?
  end
end
