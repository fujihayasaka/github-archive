# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::Attributes::BusinessTest < GitHub::TestCase

  setup do
    @actor = create(:user)
    @business = create :business
    @subject = @business.permissions_wrapper.freeze
  end

  context "subject attributes" do
    test "subject attributes" do
      attrs = @subject.subject_attributes
      assert_equal({ "subject.type" => "Business", "subject.id" => @business.id, "subject.business.id" => @business.id }, attrs)
    end
  end
end
