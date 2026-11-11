# typed: true
# frozen_string_literal: true

# An SSH public key used only for signing commits.
class GitSigningSshPublicKey < ApplicationRecord::Domain::UsersCollab
  belongs_to :user

  # MIN_KEY_BIT_LENGTH is used by the PublicKey::SharedValidations module,
  # and differs between GitSigningSshPublicKey and PublicKey
  MIN_KEY_BIT_LENGTH = 2047

  # required because sorbet does not permit dynamic constant references (5001)
  def self.min_key_bit_length
    MIN_KEY_BIT_LENGTH
  end

  include PublicKey::SharedValidations
  validates :title, unicode3: true

  after_create_commit :instrument_creation
  after_commit :instrument_deletion, on: :destroy

  after_commit  :notify_creation, on: :create

  validates :user_id, presence: true
  validate :signing_key_is_not_someone_elses_auth_key

  # NOTE: set_title must run before strip_comments since it extracts the title
  # from the comments.
  before_validation :strip_whitespace, :set_title, :strip_prefix, :strip_comments
  before_save       :set_fingerprint_sha256

  extend GitHub::Encoding
  force_utf8_encoding :fingerprint_sha256, :key

  VALID_DESTROY_REASONS = {
    # Keys which have been manually removed by the user
    removed_by_user: "Deleted by the user",

    # Keys that have been removed by GitHub Staff
    removed_by_staff: "Deleted by GitHub"
  }.freeze

  def self.destroy_explanation(reason)
    VALID_DESTROY_REASONS[reason.try(:to_sym)]
  end

  def user_has_email
    return if GitHub.enterprise?

    if user && ApplicationMailer::Helpers.user_email(user).blank?
      errors.add :base, "To be extra safe, please add an email address to your account before creating a signing key."
    end
  end

  def to_s
    key
  end

  def ==(other)
    to_s == other.to_s
  end

  def title
    self[:title].blank? && key ? key[0..25] : self[:title]
  end

  def key_type
    @key_type ||= key.split[0]
  end

  protected

  def notify_user_key_action_via_email?
    ApplicationMailer::Helpers.user_email(self.user).present?
  end

  # Called after create to send the public key added email notification.
  def notify_creation
    AccountMailer.git_signing_ssh_public_key_added(self).deliver_later if notify_user_key_action_via_email?
  end

  # Validate that the given public key is unique to the user across both the
  # `public_keys` table and the `git_signing_ssh_public_keys` table.
  def signing_key_is_not_someone_elses_auth_key
    return if !errors[:key].empty?

    cond = ["fingerprint_sha256 = ?", fingerprint_sha256]
    existing_key = PublicKey.find_by(fingerprint_sha256: fingerprint_sha256)

    if existing_key && existing_key.user_id != user_id
      errors.add :key, "is already in use"
    end
  end

  public

  include Instrumentation::Model

  def event_payload
    event = {
      git_signing_ssh_public_key_id: id,
      title: title,
      key: key,
      fingerprint: fingerprint,
      user: user,
      user_id: T.must(user).id
    }

    if GitHub.context[:actor_id]
      event[:actor_id] = GitHub.context[:actor_id]
    end
    if GitHub.context[:actor]
      event[:actor] = GitHub.context[:actor]
    end

    event
  end

  # Public: Instrument creating new git signing public keys.
  #
  # payload - event payload Hash.
  #           :actor - The User adding this public key.
  #                    Default: the user (most add their own).
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    GitHub.dogstats.increment("git_signing_ssh_public_key", tags: [
      "action:create",
      "key_bits:#{key_bit_length}",
      "key_type:#{parsed_key.algo}"
    ])
    instrument :create, payload
  end

  # Public: Instrument public key deletion.
  #
  # options - event payload Hash.
  #           :actor - The User deleting this public key.
  #           Default: the user (most remove their own).
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    instrument :delete, payload.merge(explanation: @destroy_explanation, incident: @incident_reference)
    GitHub.dogstats.increment("git_signing_ssh_public_key", tags: ["action:destroy", "explanation:#{@destroy_explanation.to_s.gsub(/_/, "-")}"])
  end

  # Public: Destroy access and instrument the deletion using the provided
  # explanation
  #
  # explanation - The reason the record is being destroyed
  #
  # Returns the result of calling destroy() on the model instance.
  def destroy_with_explanation(explanation, incident_reference: nil)
    unless self.class.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
    @incident_reference = incident_reference
    destroy
  end

  def target_for_conditional_access
    user
  end

  def readable_by?(_)
    true
  end
end
