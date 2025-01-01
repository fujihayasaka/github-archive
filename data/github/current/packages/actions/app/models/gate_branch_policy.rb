# typed: false
# frozen_string_literal: true

class GateBranchPolicy < ApplicationRecord::Domain::Repositories
  include GitHub::Validations

  belongs_to :gate
  belongs_to :repository

  validates :gate_id, presence: true
  validates :name, presence: true
  validate :name_uniqueness_by_policy_type
  validates :name, bytesize: { maximum: 1024 }
  validate :valid_name?
  after_commit :gate_branch_policies_changed, on: [:create, :update]
  after_commit :gate_branch_policies_removed, on: [:destroy]

  attribute :name, StringFromBinary.new

  PROTECTED_TAG_PREFIX = "refs/tags/gh/"

  def gate_branch_policies_changed
    previous_name = previous_changes[:name].try(:first)
    gate.environment.instrument_event(event: "update_protection_rule", gate_type: is_tag_policy? ? "tag_policy_pattern" : "branch_policy_pattern", old_value: previous_name&.delete_prefix(PROTECTED_TAG_PREFIX), new_value: name.delete_prefix(PROTECTED_TAG_PREFIX))
  end

  def gate_branch_policies_removed
    # possible that the gate or environment were already deleted
    if !gate.nil? && !gate.environment.nil?
      gate.environment.instrument_event(event: "update_protection_rule", gate_type: is_tag_policy? ? "tag_policy_pattern" : "branch_policy_pattern", old_value: name.delete_prefix(PROTECTED_TAG_PREFIX))
    end
  end

  def name
    return super&.delete_prefix(PROTECTED_TAG_PREFIX) if is_tag_policy?
    super
  end

  def is_tag_policy?
    self[:name]&.start_with?(PROTECTED_TAG_PREFIX) || false
  end

  def matches?(branch_name)
    File.fnmatch?(name, branch_name, File::FNM_PATHNAME)
  end

  private

  # From protected_branch.rb
  # Branch names can be split into different components (the parts between `/`).
  # This is a list of characters that can not be part of such a component for a rule.
  RULE_COMPONENT_CHARS = /[^\x00-\x1F\s\t\\:\^~\/]/
  VALID_RULE = /\A#{RULE_COMPONENT_CHARS}+(\/#{RULE_COMPONENT_CHARS}+)*\z/

  def valid_name?
    return if name.nil? || name.b.match?(VALID_RULE)

    errors.add :name, "is invalid"
  end

  def name_uniqueness_by_policy_type
    if is_tag_policy?
      GateBranchPolicy.where(gate_id: gate_id).where("name LIKE ?", "#{PROTECTED_TAG_PREFIX}%").pluck(:id, :name).each do |(existing_id, existing_name)|
        errors.add :name, "tag pattern already exist: #{name}" if existing_name.casecmp?(self[:name]) && existing_id != id
      end
    else
      GateBranchPolicy.where(gate_id: gate_id).where.not("name LIKE ?", "#{PROTECTED_TAG_PREFIX}%").pluck(:id, :name).each do |(existing_id, existing_name)|
        errors.add :name, "branch pattern already exists: #{name}" if existing_name.casecmp?(self[:name]) && existing_id != id
      end
    end
  end
end
