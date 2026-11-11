# typed: true
# frozen_string_literal: true

module ConfigValidations
  def self.out_of_range?(count, min, max)
    count.present? && count.is_a?(Integer) && (count > max || count < min)
  end

  def self.length_out_of_range?(obj, min, max)
    obj.present? && (obj.is_a?(String) || obj.is_a?(Array)) && (obj.length > max || obj.length < min)
  end

  def self.environment_branch_invalid?(env_config)
    env_config.dig("protected-branches").equal?(true) && env_config.dig("allowed-branch-rules")&.any?
  end
end
