# typed: true
# frozen_string_literal: true

module MemexesInsightsHelper
  JoinTable = Struct.new(:name, :join_type, :on, :table_alias) do
    def to_s
      "#{join_type} #{name} #{table_alias} ON #{on}"
    end
  end
end
