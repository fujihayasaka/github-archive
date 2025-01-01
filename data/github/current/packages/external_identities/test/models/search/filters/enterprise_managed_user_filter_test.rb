# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersEnterpriseManagedUserFilterTest < GitHub::TestCase
  fixtures do
    @emu_business = create :business, :enterprise_managed
  end

  test "generates a business_id term filter" do
    filter = Search::Filters::EnterpriseManagedUserFilter.new(business_id: @emu_business.id)

    assert_equal({ term: { business_id: @emu_business.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "generates a business_id do not exist filter" do
    filter = Search::Filters::EnterpriseManagedUserFilter.new(business_id: nil)

    assert_equal({ exists: { field: :business_id } }, filter.must_not)
    assert_nil filter.must
    assert filter.valid?
  end
end  unless GitHub.single_business_environment?
