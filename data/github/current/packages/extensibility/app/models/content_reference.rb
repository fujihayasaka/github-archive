# typed: true
# frozen_string_literal: true

class ContentReference < ApplicationRecord::Ballast

  SUPPORTED_CONTENT_TYPES = [
    IssueComment,
    PullRequestReviewComment,
    Issue,
  ]

  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  belongs_to :content, polymorphic: true
  belongs_to :user
  has_many :attachments, class_name: "ContentReferenceAttachment"

  before_create :populate_reference_hash
  before_update :prevent_updates_of_reference

  delegate :repository, :async_repository, to: :content, allow_nil: true
  delegate :owner, to: :repository, prefix: true, allow_nil: true
  delegate :target_for_conditional_access, to: :repository

  validates_presence_of :reference
  validates_presence_of :content
  validate :content_type_supported


  def self.by_repo_and_id(repo, id)
    ref = find_by(id: id)
    return nil if ref.nil?
    return nil if ref.repository != repo
    ref
  end

  # I'm not using a scope here because a scope that returns nil is the same as
  # calling .all and this method is used both to load existing records and check
  # for the existence of a record so there are cases where it will return nil.
  def self.by_content_and_reference(content, reference)
    find_by(content: content, reference_hash: sha256_reference(reference))
  end

  def self.all_by_content_and_references(content, references)
    hashes = references.map { |reference| sha256_reference(reference) }

    where(content: content, reference_hash: hashes).includes(content: [:repository])
  end

  def self.sha256_reference(reference)
    Digest::SHA256.hexdigest(reference)
  end

  def has_processed_attachment?
    T.unsafe(attachments).with_processed_state.exists?
  end

  def processed_attachment
    # We includes the integration to avoid preloading issues in the goomba pipeline
    T.unsafe(attachments).with_processed_state.includes(:integration).first
  end

  def event_payload
    {
      content_reference_id: id,
    }
  end

  def notify_integrations
    instrument(:create)
  end

  def matching_content_reference?(actor)
    installation = actor.try(:installation)

    return false if installation.nil?

    installation.content_references.any? do |content_reference|
      content_reference.matches(self.reference)
    end
  end

  def readable_by?(actor)
    repository.resources.content_references.readable_by?(actor) && matching_content_reference?(actor)
  end

  def writable_by?(actor)
    repository.resources.content_references.writable_by?(actor) && matching_content_reference?(actor)
  end

  def host
    Addressable::URI.parse(self.reference).host.downcase
  end

  private

  def populate_reference_hash
    self.reference_hash = Digest::SHA256.hexdigest(T.must(reference))
  end

  # We don't want to allow changes to the reference or reference_hash field as those
  # are the fields that contain the string/pattern we are attaching this reference
  # to within the #content.
  def prevent_updates_of_reference
    raise ActiveRecord::Rollback if reference_changed? || reference_hash_changed?
  end

  def content_type_supported
    klass = content.class
    unless SUPPORTED_CONTENT_TYPES.include?(klass)
      errors.add(:content, "#{klass.name} is not a supported content type")
    end
  end
end
