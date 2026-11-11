# typed: strict
# frozen_string_literal: true

class GitHubModels::Preset < ApplicationRecord::Domain::GitHubModels
  include GitHubModels::IPreset

  self.table_name = "models_presets"
  self.strict_loading_by_default = true
  self.ignored_columns = %w(conversation_history)

  LIMIT_PER_USER = 50
  RESERVED_DEFAULT_NAME = "Default"

  # rubocop:todo Rails/InverseOf
  belongs_to :user, class_name: "::User", required: true
  # rubocop:enable Rails/InverseOf

  before_validation :set_slug

  validates_presence_of :name, :slug, :parameters
  validates_uniqueness_of :slug
  validates_uniqueness_of :name,
    scope: :user_id,
    case_sensitive: false,
    message: "of preset already exists"

  # Even though the DB constraint for name is 255, in reality we want to limit this to 100 characters for two reasons:
  # 1. The UI in the Presets menu will look better
  # 2. The URL identifier, which is made up of user_login (max 40 chars)/name, has a DB constraint of 255 characters too
  validates :name, length: { maximum: 100 }

  validate :name_must_not_be_reserved, on: [:create, :update]
  validate :user_preset_limit_not_exceeded, on: :create
  validate :user_may_own_presets

  scope :for_user, ->(user_or_id) { where(user_id: user_or_id) }

  sig { override.params(other_user: T.nilable(::User)).returns(T::Boolean) }
  def belongs_to?(other_user)
    return false unless other_user
    user_id == other_user.id
  end

  sig { override.returns(GitHubModels::Types::Preset) }
  def json_payload
    { name: name, parameters: parsed_parameters, private: private, urlIdentifier: slug }
  end

  sig { returns(GitHubModels::Types::PresetParameters) }
  def parsed_parameters
    params_hash = parameters.is_a?(String) ? JSON.parse(parameters) : parameters
    { system_prompt: params_hash["system_prompt"] || "", chat_prompt: params_hash["chat_prompt"] || "" }
  end

  private

  sig { returns(T.nilable(String)) }
  def set_slug
    user = self.user
    return unless user && name

    self.slug = "#{user.display_login}/#{name.parameterize}"
  end

  sig { void }
  def name_must_not_be_reserved
    if name&.casecmp?(RESERVED_DEFAULT_NAME)
      errors.add(:name, "cannot be '#{RESERVED_DEFAULT_NAME}'")
    end
  end

  sig { void }
  def user_preset_limit_not_exceeded
    if user_id && self.class.for_user(user_id).count >= LIMIT_PER_USER
      errors.add(:user, "has reached the preset limit of #{LIMIT_PER_USER}")
    end
  end

  sig { void }
  def user_may_own_presets
    user = self.user
    if user && !user.user?
      errors.add(:user, "must not be of #{user.type.humanize} type")
    end
  end
end
