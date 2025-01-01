# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class GenerateNameTest < GitHub::TestCase
    fixtures do
      @owner = create(:user, login: "user-name")
      @display_name = "giggly platypus"
    end

    context "truncation" do
      test "it generates a name with all segments when short enough" do
        name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner)
        assert name.starts_with?("giggly-platypus-")
      end

      test "it does not truncate the suffix" do
        # 1234567 is the same length as -suffix
        max_length = @display_name.length
        name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner, suffix: "suffix", max_name_length: max_length)
        assert_equal "giggly-suffix", name
      end

      test "it properly respects max_name_length" do
        suffix = "suffix"
        max_length = 18
        name = Codespaces::GenerateName.call(display_name: "mydisplaynameisbad", owner: @owner, suffix: suffix, max_name_length: max_length)
        assert_equal max_length, name.length
        assert_equal "mydisplayna-suffix", name
      end
    end

    context "suffix generation" do
      test "it generates a suffix with the owner ID encoded as the first element" do
        name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner)
        suffix = name.split("-").last
        assert Codespaces.hashid.decode(suffix).first.to_s.start_with?(@owner.id.to_s)
      end

      test "it generates a unique suffix given the same repository and owner multiple times" do
        first_name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner)
        second_name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner)
        refute_equal first_name, second_name
      end

      test "it does not generate common word-producing characters" do
        5.times do
          name = Codespaces::GenerateName.call(display_name: @display_name, owner: @owner)
          suffix = name.split("-").last

          # Sanity check that none of the common word-producing characters from the suffix
          # generation in generate_unique_name are included in the suffix.
          refute suffix.match?(/[01abdeiklnostuyz]/)
        end
      end
    end
  end
end
