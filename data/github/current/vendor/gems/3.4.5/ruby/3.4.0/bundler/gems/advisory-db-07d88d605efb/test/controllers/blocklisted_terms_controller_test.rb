# frozen_string_literal: true

require "test_helper"

class BlocklistedTermsControllerTest < ActionDispatch::IntegrationTest
  test "index works with or whithout terms" do
    user = create(:user)

    get "/blocklisted_terms",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    create(:blocklisted_term, pattern: "foo")
    create(:blocklisted_term, pattern: "bar")
    create(:blocklisted_term, pattern: "baz")

    get "/blocklisted_terms",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok
  end

  test "create adds a new blocklisted term" do
    user = create(:user)

    assert_difference -> { BlocklistedTerm.count }, 1 do
      post blocklisted_terms_path,
        headers: { "X-Okta-Username" => user.email },
        params: {
          blocklisted_term: {
            pattern: "foo",
            level: "warn",
          },
        }
    end

    assert_response :found
    blocklisted_term = BlocklistedTerm.order(:id).last
    assert_equal "foo", blocklisted_term.pattern
    assert_equal "warn", blocklisted_term.level

    assert_difference -> { BlocklistedTerm.count }, 1 do
      post blocklisted_terms_path,
        headers: { "X-Okta-Username" => user.email },
        params: {
          blocklisted_term: {
            pattern: "bar",
            level: "remove",
          },
        }
    end

    assert_response :found
    blocklisted_term = BlocklistedTerm.order(:id).last
    assert_equal "bar", blocklisted_term.pattern
    assert_equal "remove", blocklisted_term.level
  end

  test "create validates the pattern" do
    user = create(:user)
    assert_no_difference -> { BlocklistedTerm.count } do
      post blocklisted_terms_path,
        headers: { "X-Okta-Username" => user.email },
        params: {
          blocklisted_term: {
            pattern: " ",
            level: "warn",
          },
        }
    end

    assert_response :unprocessable_entity
  end

  test "show lists the advisory reviews matching the term" do
    user = create(:user)
    blocklisted_term = create(:blocklisted_term, pattern: "foo")
    create_list(:advisory_review, 10, description: "this shouldn't match")
    create_list(:advisory_review, 5, description: "this foo should match")
    AdvisoryReview.apply_blocklist

    get "/blocklisted_terms/#{blocklisted_term.id}",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok
    assert_select "[data-test-selector=advisory-review-row]", count: 5
  end

  test "destroy deletes a blocklisted term" do
    user = create(:user)
    create(:blocklisted_term, pattern: "foo")
    deleted_term = create(:blocklisted_term, pattern: "bar")
    create(:blocklisted_term, pattern: "baz")

    assert_difference -> { BlocklistedTerm.count }, -1 do
      delete "/blocklisted_terms/#{deleted_term.id}", headers: { "X-Okta-Username" => user.email }
    end

    assert_response :found

    blocklist = BlocklistedTerm.order(:id).pluck(:pattern)
    assert_equal %w[foo baz], blocklist
  end
end
