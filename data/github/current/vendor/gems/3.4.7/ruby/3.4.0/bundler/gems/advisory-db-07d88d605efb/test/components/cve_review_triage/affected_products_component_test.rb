# frozen_string_literal: true

require "test_helper"

class CVEReviewTriageAffectedProductsComponent < ViewComponent::TestCase
  test "#affected_products returns an empty list of affected products if affected_products_payload given as nil" do
    affected_products_component = CVEReviewTriage::AffectedProductsComponent.new(affected_products_payload: nil)

    assert_equal 0, affected_products_component.affected_products.length
  end

  test "#affected_products returns an empty list if affected_products_payload is not defined" do
    cve_request = create(
      :cve_request,
      affected_products_payload: nil, # <--
    )

    affected_products_component = CVEReviewTriage::AffectedProductsComponent.new(affected_products_payload: cve_request.affected_products_payload)

    assert_equal 0, affected_products_component.affected_products.length
  end

  test "#affected_products returns an empty list if affected_products_payload is empty" do
    cve_request = create(
      :cve_request,
      affected_products_payload: [], # <--
    )

    affected_products_component = CVEReviewTriage::AffectedProductsComponent.new(affected_products_payload: cve_request.affected_products_payload)

    assert_equal 0, affected_products_component.affected_products.length
  end

  test "#affected_products returns multiple affected products with the data coming from affected_products_payload if that field is defined and not empty" do
    affected_products = [
      {
        package: "nodemon",
        ecosystem: "npm",
        affected_versions: "< 1.2.3",
        patches: "1.2.3",
      },
      {
        package: "gomon",
        ecosystem: "go",
        affected_versions: "< 2.3.4",
        patches: "2.3.4",
      },
      {
        package: "nugetmon",
        ecosystem: "nuget",
        affected_versions: "< 3.4.5",
        patches: "3.4.5",
      },
    ]
    cve_request = create(
      :cve_request,
      affected_products_payload: affected_products,
    )

    affected_products_component = CVEReviewTriage::AffectedProductsComponent.new(affected_products_payload: cve_request.affected_products_payload)

    assert_equal 3, affected_products_component.affected_products.length
    affected_products.each_with_index do |affected_product, index|
      assert_equal affected_product[:package], affected_products_component.affected_products[index][:package]
      assert_equal affected_product[:ecosystem], affected_products_component.affected_products[index][:ecosystem]
      assert_equal affected_product[:affected_versions], affected_products_component.affected_products[index][:affected_versions]
      assert_equal affected_product[:patches], affected_products_component.affected_products[index][:patches]
    end
  end

  test "#affected_products filters out elements whose pair of ecosystem and package values have already appeared in the list" do
    affected_products = [
      {
        package: "nodemon",
        ecosystem: "npm",
        affected_versions: "< 1.2.3",
        patches: "1.2.3",
      },
      {
        package: "gomon",
        ecosystem: "go",
        affected_versions: "< 2.3.4",
        patches: "2.3.4",
      },
      {
        package: "nodemon", # <---
        ecosystem: "npm", # <---
        affected_versions: "< 9.7.8",
        patches: "9.7.8",
      },
      {
        package: "nugetmon",
        ecosystem: "nuget",
        affected_versions: "< 3.4.5",
        patches: "3.4.5",
      },
    ]
    cve_request = create(
      :cve_request,
      affected_products_payload: affected_products,
    )

    affected_products_component = CVEReviewTriage::AffectedProductsComponent.new(affected_products_payload: cve_request.affected_products_payload)

    assert_equal 3, affected_products_component.affected_products.length
    affected_products[..1].concat(affected_products[-1..]).each_with_index do |affected_product, index|
      assert_equal affected_product[:package], affected_products_component.affected_products[index][:package]
      assert_equal affected_product[:ecosystem], affected_products_component.affected_products[index][:ecosystem]
      assert_equal affected_product[:affected_versions], affected_products_component.affected_products[index][:affected_versions]
      assert_equal affected_product[:patches], affected_products_component.affected_products[index][:patches]
    end
  end
end
