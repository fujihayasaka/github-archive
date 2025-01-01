# typed: true
# frozen_string_literal: true

class TeamMemberQueryComponents
  QUERY_COMPONENT_TYPES = {
    role: Platform::Enums::TeamMemberRole,
    membership: Platform::Enums::TeamMembershipType,
  }.freeze

  QUERY_COMPONENT_DEFAULTS = {
    membership: "IMMEDIATE",
  }.freeze

  attr_reader :query

  def initialize(query, graphql: true)
    @graphql = graphql
    @query, @values = process(query.to_s)
  end

  QUERY_COMPONENT_TYPES.each_key do |name|
    define_method(name) do
      @values[name]
    end
  end

  private

  def process(query)
    values = QUERY_COMPONENT_DEFAULTS.dup

    # pluck out matching entries
    query.scan(/[^\s]+:[^\s]+/) do |result|
      name, value = result.split(":")
      name = name.to_sym
      value = munge_value(value)
      if valid_enum_value?(name, value)
        values[name] = value
        query = query.gsub(result, "")
      end
    end

    values = munge_default(values)

    [query.strip, values]
  end

  def valid_enum_value?(name, value)
    return false unless definition = QUERY_COMPONENT_TYPES[name]

    unless @graphql
      value = value.to_s.strip.underscore.upcase.presence
    end

    definition.values.keys.include?(value)
  end

  def munge_value(value)
    if @graphql
      value.to_s.strip.underscore.upcase.presence
    else
      value.to_s.strip.underscore.downcase.presence
    end
  end

  def munge_default(values)
    return values if @graphql

    values.each_with_object({}) do |(k, v), hsh|
      if QUERY_COMPONENT_DEFAULTS[k] == v
        hsh[k] = v.downcase
      else
        hsh[k] = v
      end
    end
  end
end
