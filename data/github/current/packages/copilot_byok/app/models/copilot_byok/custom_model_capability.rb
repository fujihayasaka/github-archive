# typed: true
# frozen_string_literal: true

class CopilotByok::CustomModelCapability < ApplicationRecord::Domain::Copilot
  self.table_name = "copilot_custom_model_capabilities"

  belongs_to :custom_model, class_name: "CopilotByok::CustomModel", inverse_of: :capability, required: true,
    foreign_key: :copilot_custom_model_id
  destroy_in_background_with :custom_model

  has_one :custom_key, through: :custom_model, inverse_of: :custom_model_capabilities

  enum :endpoint_type, {
    chat_completions: 0,
    responses: 1,
  }

  validates :copilot_custom_model_id, uniqueness: true
  validates :max_output_tokens, :max_input_tokens, :max_context_window,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  sig { returns T::Hash[Symbol, T.untyped] }
  def to_twirp_user_detail
    # Reference: https://github.com/github/copilot-twirp/blob/c1127776931b8ec2b90d3de1382fa12b4549d7cb/proto/users/v1/byok.proto#L48-L51
    {
      capabilities: {
        tool_calling: tool_calling || false,
        vision: vision || false,
        thinking: thinking || false,
        streaming: streaming || false,
      },
      limits: {
        max_output_tokens: max_output_tokens,
        max_input_tokens: max_input_tokens,
        max_context_window: max_context_window,
      },
      endpoint_type: endpoint_type,
    }
  end
end
