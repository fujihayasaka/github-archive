# typed: strict
# frozen_string_literal: true

class GitHubModels::Multiplier < ApplicationRecord::Domain::GitHubModels
  self.table_name = "models_multipliers"

  belongs_to :model, class_name: "GitHubModels::Model", inverse_of: :models_multiplier,
    primary_key: :slug, foreign_key: :models_slug

  validates :models_slug, presence: true, uniqueness: true
  validates :input, :output, presence: true,
    numericality: { greater_than: 0, less_than_or_equal_to: 99999.99999 }

  TOKEN_UNIT_PRICE = 0.00001

  sig { returns(T.nilable(String)) }
  def model_details_path
    model&.details_path
  end

  sig { returns(T.nilable(String)) }
  def model_friendly_name
    model&.friendly_name
  end

  sig { returns(T.nilable(String)) }
  def to_param
    models_slug
  end

  sig { returns T.nilable(String) }
  def publisher_slug
    model&.publisher_slug
  end

  # We don't use the `models_slug` value from the database here because it doesn't match the format we require in the
  # Gateway. The `models_slug` is a concatenation of the registry and the model name. The Gateway used the publisher
  # instead of the registry.
  sig { returns T.nilable(String) }
  def model_billing_slug
    return if model.nil?
    model&.downcased_external_slug
  end

  sig { returns(GitHubModels::Types::MultiplierPayload) }
  def twirp_response
    {
      model: model_billing_slug,
      input: input.to_s,
      cached_input: cached_input&.to_s,
      output: output.to_s,
    }
  end
end
