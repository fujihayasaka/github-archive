# frozen_string_literal: true

Configs::Entry = Data.define(:name, :value, :final, :target_type, :target_id, :created_at, :updated_at) do
  def self.from_twirp_config(twirp_config)
    attributes = twirp_config.to_h
    target = attributes.delete(:target)
    attributes[:target_type] = legacy_target_type_from_proto(target[:type])
    attributes[:target_id] = target[:id]
    attributes[:created_at] = proto_to_time(attributes[:created_at])
    attributes[:updated_at] = proto_to_time(attributes[:updated_at])

    new(**attributes)
  end

  def self.proto_to_time(timestamp)
    Time.at(timestamp[:seconds], timestamp[:nanos], :nanosecond)
  end

  def self.legacy_target_type_from_proto(proto_type)
    case proto_type
    when :Repository
      'Repository'
    when :User
      'User'
    when :Business
      'Business'
    when :Global
      'global'
    end
  end
end
