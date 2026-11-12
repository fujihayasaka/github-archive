# frozen_string_literal: true

require_relative "proto/configs_pb"

module Configs
  # Target specifies a configuration target using the ownership hierarchy.
  # Use as the key for batch resolution methods (resolve_value_for_name, etc.).
  #
  # Mirrors Go's TargetWithOwners struct. Data.define provides value equality,
  # making Target usable as a hash key without normalization.
  #
  # Example:
  #   target = Configs::Target.new(repo_id: 123, owner_id: 456)
  Target = Data.define(:repo_id, :owner_id, :business_id) do
    def initialize(repo_id: nil, owner_id: nil, business_id: nil)
      super
    end

    # Returns a Configs::Twirp::ConfigTargetWithOwners proto message.
    def to_proto
      Configs::Twirp::ConfigTargetWithOwners.new(
        repo_id: repo_id,
        owner_id: owner_id,
        business_id: business_id
      )
    end

    # Returns [type_val, id] for the highest-priority non-zero identifier.
    # Priority: repo_id > owner_id > business_id > global
    # Mirrors Go's mostSpecificTarget().
    def most_specific_target
      if repo_id && repo_id != 0
        [Configs::Target::REPOSITORY, repo_id]
      elsif owner_id && owner_id != 0
        [Configs::Target::USER, owner_id]
      elsif business_id && business_id != 0
        [Configs::Target::BUSINESS, business_id]
      else
        [Configs::Target::GLOBAL, 0]
      end
    end
  end

  # Target type constants matching the proto enum values.
  Target::REPOSITORY = Configs::Twirp::TargetType.resolve(:Repository)
  Target::USER       = Configs::Twirp::TargetType.resolve(:User)
  Target::BUSINESS   = Configs::Twirp::TargetType.resolve(:Business)
  Target::GLOBAL     = Configs::Twirp::TargetType.resolve(:Global)
end
