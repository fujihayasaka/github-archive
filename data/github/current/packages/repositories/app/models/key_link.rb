# typed: true
# frozen_string_literal: true

class KeyLink < ApplicationRecord::Collab
  include GitHub::Validations
  include Instrumentation::Model

  include Repositories::IKeyLink

  belongs_to :owner, polymorphic: true
  destroy_in_background_with :owner, polymorphic_class_name: "Repository"

  # Every key prefix needs to match this regex
  KEY_PREFIX_VALIDATION_RE = %r{\A[a-z]([a-z0-9\.\-_+=:/#]{0,30}[a-z\.\-_+=:/#]){0,1}\z}i

  MAX_PER_OWNER = {
    Repository: 500,
  }

  validates :key_prefix,
    unicode3: true,
    presence: true,
    # Attention: When changing the `maximum`, make sure to adjust the length of
    # the `key_prefix` column in the `key_links` table accordingly
    # See https://github.com/github/github/pull/207191
    length: { minimum: 1, maximum: 32 }
  validates :key_prefix,
    uniqueness: {
      scope: :owner,
      case_sensitive: false
    },
    if: -> {
      T.bind(self, KeyLink)
      errors[:key_prefix].blank?
    }
  validates :url_template,
    unicode3: true,
    presence: true
  validates :owner_type,
    presence: true,
    inclusion: { in: %w[Repository] }
  validates :is_alphanumeric,
    inclusion: { in: [true, false] }
  # "Must begin with a letter" rule is important so that customers cannot override the "#<id>" issue/pull request links.
  validates_format_of :key_prefix, with: %r{\A[a-z]}i,
    message: "must begin with a letter"
  validates_format_of :key_prefix, without: %r{[0-9]\Z},
    message: "must not end with a number"
  validates_format_of :key_prefix, with: KEY_PREFIX_VALIDATION_RE,
    message: "must only contain letters, numbers, or .-_+=:/#"
  validate :ensure_url_template_valid
  validate :validate_key_link_count, on: :create
  validate :ensure_alphanumeric_prefix_does_not_match_existing, on: :create

  after_commit :instrument_creation_event, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy, unless: -> { !GitHub.elm_internal_webhooks_enabled? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_destroy :generate_webhook_payload_for_deletion, unless: -> { !GitHub.elm_internal_webhooks_enabled? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def url(number)
    url_template
      .sub(Repositories::Domain::KeyLinks::URL_NUMBER_TEMPLATE, number)
  end

  def example_key
    if is_alphanumeric
      "#{key_prefix}1a23v"
    else
      "#{key_prefix}123"
    end
  end

  def example_url
    if is_alphanumeric
      url("1a23v")
    else
      url("123")
    end
  end

  private

  def ensure_url_template_valid
    return if url_template.blank?
    if url_template.match(/\s/)
      return errors.add(:url_template, "must not contain white space")
    end
    if url_template.match(/[\"\']/)
      return errors.add(:url_template, "must not contain quotes")
    end
    uri = Addressable::URI.parse(url_template)
    unless uri.absolute?
      return errors.add(:url_template, "must be an absolute URL")
    end
    unless %w[http https].include?(uri.scheme)
      errors.add(:url_template, "must be an http(s) URL")
    end
    unless url_template.include?(Repositories::Domain::KeyLinks::URL_NUMBER_TEMPLATE)
      errors.add(:url_template,
        "is missing a #{Repositories::Domain::KeyLinks::URL_NUMBER_TEMPLATE} token")
    end
  rescue Addressable::URI::InvalidURIError
    errors.add(:url_template, "is invalid")
  end

  def validate_key_link_count
    max = MAX_PER_OWNER[owner.class.name.to_sym]
    if owner && KeyLink.where(owner: owner).count >= max
      errors.add(:base, "A maximum of #{max} autolink references may be created per #{owner.class.name}")
    end
  end

  # If the key_link is alphanumeric, then the prefix cannot match the beginning of any existing prefixes because the
  # behavior would be undefined. For example, if an alphanumeric prefix of "TICKET" already exists, then the user
  # cannot create a new prefix of "TICKETPR", because the string "TICKETPR123" could match either: It could be a match
  # for "TICKET" with a <num> of "PR123", or it could be a match for "TICKETPR" with a <num> of "123". This check can
  # theoretically be ignored in very specific cases, but explaining these situations in the docs is overkill so it's
  # just prevented entirely.
  def ensure_alphanumeric_prefix_does_not_match_existing
    return if key_prefix.blank? || errors.any? { |e| e.details[:error] == :taken }

    existing_key_links = KeyLink.where(owner: owner)
    downcased_prefix = key_prefix.downcase

    existing_key_links.each do |existing|
      downcased_existing_prefix = existing.key_prefix.downcase
      if downcased_existing_prefix.start_with?(downcased_prefix)
        errors.add(:base, "The existing prefix \"#{existing.key_prefix}\" starts with the new prefix, which could cause overlap. Please choose a different prefix.")
        break
      end
      if downcased_prefix.start_with?(downcased_existing_prefix)
        errors.add(:base, "The new prefix starts with the existing prefix \"#{existing.key_prefix}\", which could cause overlap. Please choose a different prefix.")
        break
      end
    end
  end

  def instrument_creation_event
    payload = {
      action: :created,
      autolink_id: id,
      key_prefix: key_prefix,
      url_template: url_template,
      is_alphanumeric: is_alphanumeric,
      repository_id: owner.is_a?(Repository) ? owner.id : nil
    }
    instrument :create, payload
    GitHub.dogstats.increment("key_links", tags: ["action:create", "valid:true"])
    GlobalInstrumenter.instrument("key_link.create", event_payload)
  end

  def instrument_destruction
    if GitHub.elm_internal_webhooks_enabled?
      unless defined?(@delivery_system)
        raise "'generate_webhook_payload_for_deletion' must be called before instrumenting destruction"
      end

      @delivery_system&.deliver_later
    end
  end

  def instrument_destroy
    instrument :destroy
  end

  # we need to generate the payload before the key link is deleted, so we don't lose the data
  def generate_webhook_payload_for_deletion
    event_for_delete = Hook::Event::AutolinkEvent.new(
      action: :deleted,
      autolink_id: id,
      key_prefix: key_prefix,
      url_template: url_template,
      is_alphanumeric: is_alphanumeric,
      repository_id: owner.is_a?(Repository) ? owner.id : nil,
      triggered_at: Time.now
    )
    @delivery_system = Hook::DeliverySystem.new(event_for_delete)
    @delivery_system.generate_hookshot_payloads
  end

  def event_payload
    {
      actor: User.find_by(id: GitHub.context[:actor_id]),
      key_prefix: key_prefix,
      url_template: url_template,
      is_alphanumeric: is_alphanumeric,
      repo: owner,
    }
  end
end
