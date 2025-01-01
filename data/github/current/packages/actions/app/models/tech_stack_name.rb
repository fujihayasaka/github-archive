# typed: false
# frozen_string_literal: true
require "scout/tech_stack"

class TechStackName < ApplicationRecord::Domain::TechStackNames
  include GitHub::Validations
  validates_presence_of :name
  validates :name, unicode3: true
  validates_presence_of :external_id

  def self.lookup_by_name(name)
    if stack_name = self.find_by_name(name)
      stack_name
    elsif tech_stack = Scout::TechStack.find_by_name(name) ||
      Scout::TechStack.find_by_alias(name)
      begin
        TechStackName.create! name: tech_stack.name, external_id: tech_stack.stack_id, stack_type: "st"
      rescue ActiveRecord::RecordNotUnique
        self.find_by_name(name)
      end


    elsif linguist = Linguist::Language.find_by_name(name) ||
      Linguist::Language.find_by_alias(name)
      begin
        TechStackName.create! name: linguist.name, external_id: linguist.language_id, stack_type: "ln"
      rescue ActiveRecord::RecordNotUnique
        self.find_by_name(name)
      end
    end
  end

  def to_s
    name
  end
end
