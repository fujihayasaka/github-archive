# typed: false
# frozen_string_literal: true

class RepositoryStack < ApplicationRecord::Domain::Repositories
  include GitHub::Validations
  include Instrumentation::Model


  extend GitHub::Encoding
  force_utf8_encoding :description

  self.table_name = "repository_stacks"
  belongs_to :repository, class_name: "Repository"
  has_one :analytics, class_name: "StacksAnalytic", dependent: :destroy, primary_key: :repository_id, foreign_key: :template_repository_id, inverse_of: :template_repository

  MIN_STARS_FOR_SOCIAL_PROOF = 2
  DESCRIPTION_MAX_LENGTH = 125
  ENDING_PUNCTUATION_REGEX = /[\.,!?]+\z/

  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, if: :listed?
  validates_format_of :color, with: /\A[0-9a-f]{6}\z/iu
  validates_with RepositoryActions::SlugValidator, if: :slug_changed?
  validates :slug, presence: true, unicode3: true, if: :listed?
  validate :validate_name_and_slug

  validate :validate_published_release, if: :listed?
  validates :security_email, presence: true, if: [:listed?, :owned_by_org?]

  delegate :owner, to: :repository

  # Returns RepositoryStacks that the given User owns or can manage because they're owned by an
  # Organization for which the given User is an admin.
  scope :adminable_by, -> (user) {
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    where(repository_id: user.associated_repository_ids(min_action: :admin))
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  }

  has_many :repository_stack_releases
  has_many :releases, through: :repository_stack_releases

  has_many :published_stack_releases,
    -> { where(published_on_marketplace: true) },
    class_name: "RepositoryStackRelease"

  has_many :published_releases,
    -> { published },
    through: :published_stack_releases,
    source: :release

  before_validation :set_color
  before_validation :set_icon_name
  before_validation :remove_description_punctuation
  before_validation :set_slug, if: [:name_changed?, :listed?]

  delegate :owner, to: :repository

  scope :featured, -> { where(featured: true) }
  scope :not_in_marketplace, -> { where.not(state: :listed) }
  scope :owned_by, -> (id) { joins(:repository).where("repositories.owner_id = ?", id) }
  scope :owned_by_login, -> (login) { joins(:repository).and(Repository.where(owner_login: login)) }

  scope :with_name, -> (name) { where("CONVERT(repository_stacks.name USING utf8mb4) LIKE ?", "%#{name}%") }
  scope :with_state, -> (state) { where(state: state) }

  enum :state, { unlisted: 0, listed: 10, delisted: 20 }

  def readme(committish: nil)
    async_readme(committish: committish).sync
  end

  def async_readme(committish:)
    async_repository.then do |repository|
      repository.async_default_branch.then do |_branch|
        committish_or_default = committish.presence || repository.default_branch

        PreferredFile.find(
          directory: repository.directory(committish_or_default, ""),
          subdirectories: %w(.),
          type: :readme,
        )
      end
    end
  end

  def sign_developer_agreement(actor:, agreement:, org: nil)
    return [agreement, false] unless agreement

    unless adminable_by?(actor)
      agreement.errors.add(:base, "Must have write access to sign for this Stack")
      return [agreement, false]
    end

    if org.present? && !org.adminable_by?(actor)
      agreement.errors.add(:base, "Must have org admin access to sign for this Stack")
      return [agreement, false]
    end

    if org.present?
      [agreement.sign(user: actor, organization: org), agreement]
    else
      [agreement.sign(user: actor), agreement]
    end
  end

  def has_signed_integrator_agreement?(user:, agreement: nil)
    agreement ||= Marketplace::Agreement.latest_for_integrators

    agreement && agreement.integrator? && agreement.signed_by?(user)
  end

  def org_has_signed_integrator_agreement?(org:, agreement: nil)
    return false if org.nil?

    agreement ||= Marketplace::Agreement.latest_for_integrators

    agreement && agreement.integrator? && agreement.signed_for?(org)
  end

  def verified_owner?
    owner.present? && owner.organization? && owner.creator_verification_state? == 2
  end

  #TODO: Fetch from a stacks source
  def icon_color
    RepositoryActions::Colors::ICON_COLOR_MAPPING[color]
  end

  def delist_if_unreleased
    return unless listed? && repository_stack_releases.published.empty?
    delisted!
  end

  def update_from_config!(ref = nil)
    ref = repository.default_branch if ref.nil?
    oid = repository.ref_to_sha(ref)
  rescue GitRPC::Error
    nil
  end

  def listed!
    set_slug
    super

    instrument :listed
  end

  def delisted!
    super

    repository_stack_releases.update_all(published_on_marketplace: false)
    instrument :delisted
  end

  def metadata_file
    oid = repository.ref_to_sha(repository.default_branch)
    repository.tree_entry(oid, ".github/stacks/stack.yml")
  rescue GitRPC::Error
    # GitRPC::InvalidFullOid will happen if default_branch doesn't exist.
    # GitRPC::NoSuchPath will happen if Dockerfile doesn't exist.
    nil
  end

  def config_from_metadata_file
    {}
  end

  def set_slug
    self.slug = repository.name_with_owner.encode("utf-8", undef: :replace, replace: "").parameterize
  end

  def event_payload
    {
      :repository_stack => self,
      :repo => repository,
      owner.event_prefix.to_sym => owner,
    }
  end

  def event_context(prefix: event_prefix)
    {
      prefix.to_sym => slug,
      "#{prefix}_id".to_sym => id,
    }
  end

  def owned_by_org?
    repository.owner.organization?
  end

  def adminable_by?(user)
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    user.associated_repository_ids(min_action: :write).include?(repository_id)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  end

  #hardcoding stack file name for now
  def stack_file_name
    "stack.yml"
  end

  def path
    ".github/stacks/stack.yml"
  end

  def repository_disabled?
    repository.disabled_at.present?
  end

  def can_remove_from_search_index?
    destroyed? || delisted? || repository.private? || repository_disabled?
  end

  def can_viewer_see?(current_user)
    repository.visible_and_readable_by?(current_user)
  end

  # Public: Feature or delist a stack
  #
  # inputs - Hash with values expected for featured, delist and stack_id
  #
  # Returns the updated stack
  def self.admin_update(inputs, current_user:)
    repository_stack = RepositoryStack.find_by_id(inputs[:stack_id])

    raise Errors::StackUpdateError.new("Repository Stack with ID of #{inputs[:stack_id]} not found") unless repository_stack

    viewer_is_admin = current_user.can_admin_repository_stacks?

    if inputs[:delist]
      raise Errors::StackUpdateError.new("#{repository_stack.name} not listed") unless repository_stack&.listed?

      unless repository_stack.adminable_by?(current_user) || viewer_is_admin
        error_message = "#{current_user.login} does not have permission to delist the Repository Stack"
        raise Errors::StackUpdateError.new(error_message)
      end

      repository_stack.delisted!
    end

    if inputs.has_key?(:featured)
      raise Errors::StackUpdateError.new("#{current_user.login} does not have permission to feature the Stack.") unless viewer_is_admin
      repository_stack.featured = inputs[:featured]
    end

    if repository_stack.save
      repository_stack
    else
      raise Errors::StackUpdateError.new("Unable to update #{repository_stack.name}")
    end
  end

  private

  def set_color
    primer_color = RepositoryActions::Colors.select_by_name_or_hex(color) #TODO Fetch from stacks ref

    if primer_color.present?
      self.color = primer_color[:color_hex]
    else
      self.color = RepositoryActions::Colors.generate_default_color(name || "")[:color_hex]
    end

  end

  def remove_description_punctuation
    return unless self.description

    self.description = self.description.gsub(ENDING_PUNCTUATION_REGEX, "")
  end

  # If icon name is invalid, we leave it blank and the UI uses the first letter of the Stack Name as the icon
  def set_icon_name
    return unless icon_name

    icon_name.downcase!

    self.icon_name = nil unless RepositoryActions::Icons::NAMES.include? icon_name # TODO create a new set for Stacks
  end

  def validate_published_release
    return if repository_stack_releases.where(published_on_marketplace: true).exists?

    errors.add(:state, "Stack needs a release to be listed")
  end

  def validate_name_and_slug
    return if slug.blank?
    return unless existing_stack = RepositoryStack.find_by(slug: slug)
    return if existing_stack.id == id
    return if existing_stack.repository_id == repository_id
    errors.add(:slug, "has already been taken")
  end
end
