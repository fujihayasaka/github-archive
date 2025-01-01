# typed: true
# frozen_string_literal: true

require "test_helper"

class RESTPaginatorTest < GitHub::TestCase
  # This is used as a placeholder for required values
  # (default_per_page, max_per_page) when irrelevant
  # to the test at hand.
  #
  # The value is fairly arbitrary, but needs to be bigger
  # than the per_page being used, since the value of max_per_page
  # influences the per_page value if it is smaller than per_page.
  #
  # Since neither default_per_page or max_per_page are user-input,
  # we do not have any validation or coersion for them.
  A_VALUE = 10

  def test_empty_collection
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 0, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 1, paginator.last_page

    refute_predicate paginator, :previous?
    refute_predicate paginator, :next?
  end

  # Single page collection: same first and last page.
  def test_single_page_collection_with_partial_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 1, paginator.last_page

    refute_predicate paginator, :previous?
    refute_predicate paginator, :next?
  end

  def test_single_page_collection_with_full_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 2, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 1, paginator.last_page

    refute_predicate paginator, :previous?
    refute_predicate paginator, :next?
  end

  # Two page collection: first and last pages, but no middle.
  def test_incomplete_two_page_collection_on_first_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 3, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 2, paginator.last_page

    refute_predicate paginator, :previous?

    assert_predicate paginator, :next?
    assert_equal 2, paginator.next_page
  end

  def test_incomplete_two_page_collection_on_last_page
    paginator = Rest::Paginator.new(page: 2, per_page: 2, collection_size: 3, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 2, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    refute_predicate paginator, :next?
  end

  def test_full_two_page_collection_on_first_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 4, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 2, paginator.last_page

    refute_predicate paginator, :previous?

    assert_predicate paginator, :next?
    assert_equal 2, paginator.next_page
  end

  def test_full_two_page_collection_on_last_page
    paginator = Rest::Paginator.new(page: 2, per_page: 2, collection_size: 4, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 2, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    refute_predicate paginator, :next?
  end

  # Three page collection: has beginning, middle, and end.
  def test_incomplete_three_page_collection_on_first_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 5, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    refute_predicate paginator, :previous?

    assert_predicate paginator, :next?
    assert_equal 2, paginator.next_page
  end

  def test_incomplete_three_page_collection_on_middle_page
    paginator = Rest::Paginator.new(page: 2, per_page: 2, collection_size: 5, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    assert_predicate paginator, :next?
    assert_equal 3, paginator.next_page
  end

  def test_incomplete_three_page_collection_on_last_page
    paginator = Rest::Paginator.new(page: 3, per_page: 2, collection_size: 5, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 2, paginator.previous_page

    refute_predicate paginator, :next?
  end

  def test_full_three_page_collection_on_first_page
    paginator = Rest::Paginator.new(page: 1, per_page: 2, collection_size: 6, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    refute_predicate paginator, :previous?

    assert_predicate paginator, :next?
    assert_equal 2, paginator.next_page
  end

  def test_full_three_page_collection_on_middle_page
    paginator = Rest::Paginator.new(page: 2, per_page: 2, collection_size: 6, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    assert_predicate paginator, :next?
    assert_equal 3, paginator.next_page
  end

  def test_full_three_page_collection_on_last_page
    paginator = Rest::Paginator.new(page: 3, per_page: 2, collection_size: 6, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 2, paginator.previous_page

    refute_predicate paginator, :next?
  end

  # Defaults and normalization.
  def test_page_is_1_if_not_passed
    paginator = Rest::Paginator.new(collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_page_is_1_if_passed_nil
    paginator = Rest::Paginator.new(page: nil, collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_page_is_1_if_passed_0
    paginator = Rest::Paginator.new(page: 0, collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_page_is_1_if_passed_negative_number
    paginator = Rest::Paginator.new(page: -1, collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_page_is_1_if_passed_nonnumeric_value_with_to_i_implementation
    paginator = Rest::Paginator.new(page: "bogus", collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_page_is_1_if_passed_value_that_cannot_be_coerced_into_integer
    paginator = Rest::Paginator.new(page: {}, collection_size: 1, default_per_page: A_VALUE, max_per_page: A_VALUE)
    assert_equal 1, paginator.page
  end

  def test_per_page_gets_default_if_not_passed
    paginator = Rest::Paginator.new(default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_gets_default_if_passed_nil
    paginator = Rest::Paginator.new(per_page: nil, default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_gets_default_if_passed_0
    paginator = Rest::Paginator.new(per_page: 0, default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_gets_default_if_passed_negative_number
    paginator = Rest::Paginator.new(per_page: -1, default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_gets_default_if_passed_nonnumeric_value_with_to_i_implementation
    paginator = Rest::Paginator.new(per_page: "bogus", default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_gets_default_if_passed_value_that_cannot_be_coerced_into_integer
    paginator = Rest::Paginator.new(per_page: {}, default_per_page: 3, max_per_page: A_VALUE)
    assert_equal 3, paginator.per_page
  end

  def test_max_per_page_overrides_default_per_page_if_new_max_is_smaller_than_default_per_page
    paginator = Rest::Paginator.new(per_page: nil, default_per_page: 4, max_per_page: 3)
    assert_equal 3, paginator.per_page
  end

  def test_per_page_cannot_exceed_max_per_page
    paginator = Rest::Paginator.new(per_page: 3, max_per_page: 2, default_per_page: A_VALUE)
    assert_equal 2, paginator.per_page
  end

  def test_out_of_bounds_page_uses_last_page_for_previous
    paginator = Rest::Paginator.new(page: 100, per_page: 2, collection_size: 5, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 3, paginator.previous_page

    refute_predicate paginator, :next?
  end

  def test_cannot_compute_pages_without_collection_size
    paginator = Rest::Paginator.new(collection_size: nil, default_per_page: A_VALUE, max_per_page: A_VALUE)
    [
      :first_page,
      :last_page,
      :previous_page,
      :next_page,
      :previous?,
      :next?,
    ].each do |method|
      assert_raises Rest::Paginator::CannotComputeError do
        paginator.send method
      end
    end
  end

  def test_set_deferred_collection_size
    paginator = Rest::Paginator.new(page: 2, per_page: 2, default_per_page: A_VALUE, max_per_page: A_VALUE)
    paginator.collection_size = 5

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    assert_predicate paginator, :next?
    assert_equal 3, paginator.next_page
  end

  # We don't do any caching, but we could very easily introduce memoization.
  # If we do, this should keep us honest.
  def test_reset_collection_size_recalculates
    paginator = Rest::Paginator.new(page: 2, per_page: 2, collection_size: 5, default_per_page: A_VALUE, max_per_page: A_VALUE)

    assert_equal 1, paginator.first_page
    assert_equal 3, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    assert_predicate paginator, :next?
    assert_equal 3, paginator.next_page

    paginator.collection_size = 3

    assert_equal 1, paginator.first_page
    assert_equal 2, paginator.last_page

    assert_predicate paginator, :previous?
    assert_equal 1, paginator.previous_page

    refute_predicate paginator, :next?
  end
end
