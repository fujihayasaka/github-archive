# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesLegacyPrebuildTemplateValidatorTest < GitHub::TestCase
  include CodespacesPlanFixtures

  class ARandomClass
    include ActiveModel::Validations

    validates_with Codespaces::LegacyPrebuildTemplateValidator

    attr_accessor :repository,
    :location,
    :vscs_target,
    :vscs_target_url,
    :oid,
    :sku_name,
    :branch

    def initialize(
      repository:,
      vscs_target:,
      vscs_target_url:,
      location:,
      sku_name:,
      oid:,
      branch:
      )
      @repository = repository
      @location = location
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
      @oid = oid
      @branch = branch
      @sku_name = sku_name
    end
  end

  def valid_random_class
    prebuild_template = build(:codespace_prebuild_template)
    ARandomClass.new(
      repository: prebuild_template.repository,
      vscs_target: prebuild_template.vscs_target,
      vscs_target_url: prebuild_template.vscs_target_url,
      location: prebuild_template.location,
      sku_name: prebuild_template.sku_name,
      oid: prebuild_template.oid,
      branch: prebuild_template.branch
    )
  end

  context "valid?" do
    test "validates a valid class" do
      assert_predicate valid_random_class, :valid?
    end

    test "validates :branch, :location, :oid, :repository present" do

      invalid_class = valid_random_class
      invalid_class.branch = nil
      invalid_class.location = nil
      invalid_class.oid = nil
      invalid_class.repository = nil

      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:branch], "must be present"
      assert_includes invalid_class.errors[:location], "must be present"
      assert_includes invalid_class.errors[:repository], "must be present"
    end

    test "validates url and vscs_targets" do
      invalid_class = valid_random_class

      invalid_class.vscs_target = :local
      invalid_class.vscs_target_url = nil

      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:vscs_target_url], "must be present when vscs_target is local"

      invalid_class.vscs_target = "local"
      invalid_class.vscs_target_url = nil

      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:vscs_target_url], "must be present when vscs_target is local"

      invalid_class.vscs_target = :production
      invalid_class.vscs_target_url = "localhost:3000"

      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:vscs_target_url], "must be blank when vscs_target is not local"

      invalid_class.vscs_target = nil
      invalid_class.vscs_target_url = nil

      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:vscs_target], "must be present"
    end

    test "validates plan" do
      invalid_class = valid_random_class
      invalid_class.location = nil
      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:plan], "No plan found for location and vscs_target"

      invalid_class = valid_random_class
      invalid_class.vscs_target = nil
      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:plan], "No plan found for location and vscs_target"

      invalid_class = valid_random_class
      invalid_class.vscs_target = :ppe
      invalid_class.location = "test"
      refute_predicate invalid_class, :valid?
      assert_includes invalid_class.errors[:plan], "No plan found for location and vscs_target"
    end
  end

end
