# typed: strict
# frozen_string_literal: true

class GitHubModels::Preset < ApplicationRecord::Domain::Integrations
  self.table_name = "azure_models_presets"
  self.strict_loading_by_default = true
  self.ignored_columns = %w(conversation_history)

  LIMIT_PER_USER = 50
  RESERVED_DEFAULT_NAME = "Default"

  # rubocop:todo Rails/InverseOf
  belongs_to :user, class_name: "::User", foreign_key: :user_id, strict_loading: false
  # rubocop:enable Rails/InverseOf

  validates_presence_of :name, :url_identifier, :user, :parameters

  validates_uniqueness_of :url_identifier
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

  before_validation :set_url_identifier

  JSON_KEYS = T.let(%i[name parameters private url_identifier].freeze, T::Array[Symbol])

  sig { returns(T.nilable(String)) }
  def set_url_identifier
    return unless user && name

    self.url_identifier = "#{T.must(user).display_login}/#{name.parameterize}"
  end

  sig { params(this_user: T.nilable(::User)).returns(T::Boolean) }
  def belongs_to?(this_user)
    self.user_id == this_user&.id
  end

  sig { returns(GitHubModels::Types::Preset) }
  def json_payload
    {
      name: name,
      parameters: parsed_parameters,
      private: private,
      urlIdentifier: url_identifier,
    }
  end

  sig { returns(GitHubModels::Types::PresetParameters) }
  def parsed_parameters
    raw_params = JSON.parse(parameters)

    {
      system_prompt: raw_params["system_prompt"] || "",
      chat_prompt: raw_params["chat_prompt"] || "",
    }
  end

  sig { void }
  def name_must_not_be_reserved
    if name.casecmp?(RESERVED_DEFAULT_NAME)
      errors.add(:name, "cannot be '#{RESERVED_DEFAULT_NAME}'")
    end
  end

  sig { void }
  def user_preset_limit_not_exceeded
    if self.class.for_user(user).count >= LIMIT_PER_USER
      errors.add(:base, "User has reached the preset limit of #{LIMIT_PER_USER}")
    end
  end

  sig { void }
  def user_may_own_presets
    if user && !T.must(user).user?
      errors.add(:user, "must not be of #{T.must(user).type.humanize} type")
    end
  end
end
