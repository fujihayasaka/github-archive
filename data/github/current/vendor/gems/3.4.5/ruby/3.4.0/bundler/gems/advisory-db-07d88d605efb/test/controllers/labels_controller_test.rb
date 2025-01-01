# frozen_string_literal: true

require "test_helper"

class LabelsControllerTest < ActionDispatch::IntegrationTest
  test "index works with or whithout terms" do
    user = create(:user)

    get "/labels",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    create(:label, name: "foo")
    create(:label, name: "bar")
    create(:label, name: "baz")

    get "/labels",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok
  end

  test "create adds a new label" do
    user = create(:user)

    assert_difference -> { Label.count }, 1 do
      post labels_path,
        headers: { "X-Okta-Username" => user.email },
        params: {
          label: {
            name: "foo",
            color: "abc",
            label_settings: {
              hold_publication: "1",
            },
          },
        }
    end

    assert_response :found
    label = Label.order(:id).last
    assert_equal "foo", label.name
    assert_equal "aabbcc", label.color
    assert label.label_settings.hold_publication?
  end

  test "update saves changes to a label" do
    user = create(:user)
    label = create(:label)

    assert_no_difference -> { Label.count } do
      put "/labels/#{label.id}",
        headers: { "X-Okta-Username" => user.email },
        params: {
          label: {
            name: "updated foo",
            color: "ceef2e",
            label_settings: {
              hold_publication: "1",
            },
          },
        },
        as: :json
    end

    label.reload
    assert_equal "updated foo", label.name
    assert_equal "ceef2e", label.color
    assert label.label_settings.hold_publication?
  end

  test "show lists the advisory reviews matching the label" do
    user = create(:user)
    label = create(:label, name: "foo")
    create_list(:advisory_review, 10, description: "this shouldn't match")
    labelled = create_list(:advisory_review, 5, description: "this foo should match")
    label.advisory_reviews = labelled

    get "/labels/#{label.id}",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok
    assert_select "[data-test-selector=advisory-review-row]", count: 5
  end

  test "destroy deletes a label" do
    user = create(:user)
    create(:label, name: "foo")
    deleted_label = create(:label, name: "bar")
    create(:label, name: "baz")

    assert_difference -> { Label.count }, -1 do
      delete "/labels/#{deleted_label.id}", headers: { "X-Okta-Username" => user.email }
    end

    assert_response :found

    labels = Label.order(:id).pluck(:name)
    assert_equal %w[foo baz], labels
  end
end
