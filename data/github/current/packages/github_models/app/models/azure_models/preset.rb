# typed: strict
# frozen_string_literal: true

class AzureModels::Preset < ApplicationRecord::Domain::Integrations
  include GitHub::Memoizer

  self.table_name = "azure_models_presets"
  self.strict_loading_by_default = true

  LIMIT_PER_USER = 50
  MAX_CONVERSATION_HISTORY_SIZE = T.let(1.megabytes, Integer)
  RESERVED_DEFAULT_NAME = "Default"

  # rubocop:todo Rails/InverseOf
  belongs_to :user, class_name: "::User", foreign_key: :user_id, strict_loading: false
  # rubocop:enable Rails/InverseOf

  validates_presence_of :name, :url_identifier, :user
  validates_presence_of :conversation_history, :parameters

  validates_uniqueness_of :url_identifier
  validates_uniqueness_of :name,
    scope: :user_id,
    case_sensitive: false,
    message: "of preset already exists"

  # Even though the DB constraint for name is 255, in reality we want to limit this to 100 characters for two reasons:
  # 1. The UI in the Presets menu will look better
  # 2. The URL identifier, which is made up of user_login (max 40 chars)/name, has a DB constraint of 255 characters too
  validates :name, length: { maximum: 100 }
  validates :description, length: { maximum: 255 }

  validate :name_must_not_be_reserved, on: [:create, :update]
  validate :conversation_history_size, on: [:create, :update]
  validate :user_preset_limit_not_exceeded, on: :create

  scope :for_user, ->(user_or_id) { where(user_id: user_or_id) }

  before_validation :set_url_identifier

  JSON_KEYS = T.let(%i[conversation_history description name parameters private url_identifier].freeze, T::Array[Symbol])

  sig { returns(T.nilable(String)) }
  def set_url_identifier
    return unless user && name

    self.url_identifier = "#{T.must(user).display_login}/#{name.parameterize}"
  end

  sig { params(this_user: T.nilable(User)).returns(T::Boolean) }
  def belongs_to?(this_user)
    self.user_id == this_user&.id
  end

  sig { returns(GitHubModels::Types::Preset) }
  def json_payload
    {
      conversationHistory: parsed_conversation_history,
      description: description,
      name: name,
      parameters: parsed_parameters,
      private: private,
      urlIdentifier: url_identifier,
    }
  end

  sig { returns(T::Array[T.untyped]) }
  def parsed_conversation_history
    JSON.parse(conversation_history)
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def parsed_parameters
    JSON.parse(parameters)
  end

  sig { void }
  def name_must_not_be_reserved
    if name.casecmp?(RESERVED_DEFAULT_NAME)
      errors.add(:name, "cannot be '#{RESERVED_DEFAULT_NAME}'")
    end
  end

  sig { void }
  def conversation_history_size
    if conversation_history&.bytesize.to_i > MAX_CONVERSATION_HISTORY_SIZE
      errors.add(:conversation_history, "cannot exceed #{MAX_CONVERSATION_HISTORY_SIZE / 1.megabyte} MB")
    end
  end

  sig { void }
  def user_preset_limit_not_exceeded
    if AzureModels::Preset.for_user(user).count >= LIMIT_PER_USER
      errors.add(:base, "User has reached the preset limit of #{LIMIT_PER_USER}")
    end
  end
end
