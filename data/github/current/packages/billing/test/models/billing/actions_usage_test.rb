# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ActionsUsageTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  fixtures do
    @user = create(:user, plan: GitHub::Plan.pro)
    @business = create(:business, :with_azure_subscription)
  end

  context "#has_error?" do
    test "returns true if api request raises an error" do
      GitHub.flipper[:actions_product_usage_refactor].disable
      mock_list_product_usage_response_error
      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert actions_usage.has_error?
    end

    test "returns false if api request did NOT raise an error" do
      mock_list_product_usage_response(product: "actions", sku_name: "linux", unit_of_measure: "Hours", quantity: 65)
      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      refute actions_usage.has_error?
    end
  end

  context "#total_minutes_used" do
    test "returns the total minutes used" do
      mock_list_product_usage_response(product: "actions", sku_name: "linux", unit_of_measure: "Hours", quantity: 65)
      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert_equal 65, actions_usage.total_minutes_used
    end
  end

  context "#total_paid_minutes_used" do
    test "returns the total paid minutes used" do
      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert_equal 0, actions_usage.total_paid_minutes_used

      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: @user.plan.actions_included_private_minutes + 100,
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user, additional_private_minutes: 15)

      assert_equal 115, actions_usage.total_paid_minutes_used
    end
  end

  context "#total_paid_minutes_used" do
    test "returns the number of minutes past the included private minutes" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: @user.plan.actions_included_private_minutes + 100,
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user, additional_private_minutes: 5)

      assert_equal 105, actions_usage.total_paid_minutes_used
    end
  end

  test "#total_billable_usage_pricing" do
    mock_list_product_usage_response(
      product: "actions",
      sku_name: "linux",
      unit_of_measure: "Hours",
      quantity: 0,
      additional_product_usages:
        [{
          product: {
            name: "actions"
          },
          product_sku: {
            name: "macos",
          },
          usage: {
            estimated_cost: { subunits: 500.0 },
            effective_quantity: 500.0,
          }
        },
        {
          product: {
            name: "actions"
          },
          product_sku: {
            name: "linux_4_core",
          },
          usage: {
            estimated_cost: { subunits: 800.0 },
            effective_quantity: 800.0,
          }
        }]
    )

    actions_usage = ::Billing::ActionsUsage.product_usage(@user)

    assert_equal actions_usage.total_billable_usage_pricing, Billing::Money.new(800)
  end

  context "#minutes_used_per_runtime" do
    test "returns number of private billable minutes used with refactor feature flag disabled" do
      GitHub.flipper[:actions_product_usage_refactor].disable(@business)

      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = {
        "MACOS" => 500,
        "UBUNTU" => 100,
        "WINDOWS" => 800,
        "macos_12_core" => 0,
        "ubuntu_4_core" => 0,
        "ubuntu_8_core" => 0,
        "ubuntu_16_core" => 0,
        "ubuntu_32_core" => 0,
        "ubuntu_64_core" => 0,
        "windows_4_core" => 0,
        "windows_8_core" => 0,
        "windows_16_core" => 0,
        "windows_32_core" => 0,
        "windows_64_core" => 0,
        "total" => 1400
      }

      assert_equal(expected_usage, actions_usage.minutes_used_per_runtime)
    end

    test "returns number of private billable minutes used with refactor feature flag enabled" do
      GitHub.flipper[:actions_product_usage_refactor].enable(@business)

      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = {
        "MACOS" => 500,
        "UBUNTU" => 100,
        "WINDOWS" => 800,
        "macos_12_core" => 0,
        "ubuntu_4_core" => 0,
        "ubuntu_8_core" => 0,
        "ubuntu_16_core" => 0,
        "ubuntu_32_core" => 0,
        "ubuntu_64_core" => 0,
        "windows_4_core" => 0,
        "windows_8_core" => 0,
        "windows_16_core" => 0,
        "windows_32_core" => 0,
        "windows_64_core" => 0,
        "total" => 1400
      }

      assert_equal(expected_usage, actions_usage.minutes_used_per_runtime)
    end
  end

  context "#total_standard_runners_minutes_used" do
    test "returns just the 'TOTAL' value" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)

      assert_equal(1400, actions_usage.total_standard_runners_minutes_used)
    end
  end

  context "#total_standard_runners_minutes_used" do
    test "returns number of private standard runner billable minutes used" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 1400

      assert_equal(expected_usage, actions_usage.total_standard_runners_minutes_used)
    end

    test "returns number of private standard runner billable minutes used with custom runner usage present" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 0,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "linux_4_core",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 500

      assert_equal(expected_usage, actions_usage.total_standard_runners_minutes_used)
    end

    test "returns number of private standard runner billable minutes used with macos-12 xl usage present" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 0,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos_12_core",
            },
            usage: {
              estimated_cost: { subunits: 200.0 },
              effective_quantity: 200.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 500

      assert_equal(expected_usage, actions_usage.total_standard_runners_minutes_used)
    end
  end

  context "#total_custom_runners_minutes_used" do
    test "returns number of ONLY custom runner billable minutes used" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "linux_4_core",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows_64_core",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 200.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 1000

      assert_equal(expected_usage, actions_usage.total_custom_runners_minutes_used)
    end

    test "returns number of ONLY custom runner billable minutes used with macos-12 xl usage" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos_12_core",
            },
            usage: {
              estimated_cost: { subunits: 200.0 },
              effective_quantity: 200.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "linux_4_core",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 800.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "windows_64_core",
            },
            usage: {
              estimated_cost: { subunits: 800.0 },
              effective_quantity: 200.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 1000

      assert_equal(expected_usage, actions_usage.total_custom_runners_minutes_used)
    end

    context "#fetch_usage_quote" do
      test "when custom and standard usage is present" do
        GitHub.flipper[:actions_product_usage_refactor].enable(@business)

        mock_calculate_usage_quotes_response(usage_quotes: [
          {
            product_name: "actions",
            product_sku_name: "linux",
            total_proposed_usage: { effective_quantity: 100, estimated_cost: { currency_code: "USD", subunits: 0 } },
          },
          {
            product_name: "actions",
            product_sku_name: "linux_8_core",
            total_proposed_usage: { effective_quantity: 100, estimated_cost: { currency_code: "USD", subunits: 0 } },
          },
        ])

        actions_usage = ::Billing::ActionsUsage.usage_quote(@business)
        expected_usage = {
          "MACOS"           => 0,
          "UBUNTU"          => 100.0,
          "WINDOWS"         => 0,
          "macos_12_core"   => 0,
          "ubuntu_4_core"   => 0,
          "ubuntu_8_core"   => 100.0,
          "ubuntu_16_core"  => 0,
          "ubuntu_32_core"  => 0,
          "ubuntu_64_core"  => 0,
          "windows_4_core"  => 0,
          "windows_8_core"  => 0,
          "windows_16_core" => 0,
          "windows_32_core" => 0,
          "windows_64_core" => 0,
          "total"           => 200.0
        }

        assert_equal(expected_usage, actions_usage.minutes_used_per_runtime_from_api.to_h)
      end

      test "when custom and standard usage is present without feature flag" do
        GitHub.flipper[:actions_product_usage_refactor].disable(@business)

        mock_calculate_usage_quotes_response(usage_quotes: [
          {
            product_name: "actions",
            product_sku_name: "linux",
            total_proposed_usage: { effective_quantity: 100, estimated_cost: { currency_code: "USD", subunits: 0 } },
          },
          {
            product_name: "actions",
            product_sku_name: "linux_8_core",
            total_proposed_usage: { effective_quantity: 100, estimated_cost: { currency_code: "USD", subunits: 0 } },
          },
        ])

        actions_usage = ::Billing::ActionsUsage.usage_quote(@business)
        expected_usage = {
          "total" => 100.0
        }

        assert_equal(expected_usage, actions_usage.minutes_used_per_runtime_from_api.to_h)
      end
    end

    context "#fetch_account_usage" do
      test "when custom and standard usage is present" do
        GitHub.flipper[:actions_product_usage_refactor].enable(@business)

        mock_list_account_usage_response([
          { product: "actions", sku_name: "linux", unit_of_measure: "Hours", quantity: 100, account_id: @business.id },
          { product: "actions", sku_name: "linux_8_core", unit_of_measure: "Hours", quantity: 100, account_id: @business.id },
        ])

        actions_usage = ::Billing::ActionsUsage.account_usage(@business)
        expected_usage = {
          "MACOS"           => 0,
          "UBUNTU"          => 100.0,
          "WINDOWS"         => 0,
          "macos_12_core"   => 0,
          "ubuntu_4_core"   => 0,
          "ubuntu_8_core"   => 100.0,
          "ubuntu_16_core"  => 0,
          "ubuntu_32_core"  => 0,
          "ubuntu_64_core"  => 0,
          "windows_4_core"  => 0,
          "windows_8_core"  => 0,
          "windows_16_core" => 0,
          "windows_32_core" => 0,
          "windows_64_core" => 0,
          "total"           => 200.0
        }
        assert_equal(expected_usage, actions_usage.minutes_used_per_runtime_from_api.to_h)
      end
    end
  end

  context "#total_macos_runners_minutes_used" do
    test "returns number of ONLY macos 12-core runner billable minutes used" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos_12_core",
            },
            usage: {
              estimated_cost: { subunits: 200.0 },
              effective_quantity: 200.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@business)
      expected_usage = 200

      assert_equal(expected_usage, actions_usage.total_macos_runners_minutes_used)
    end
  end

  context "#total_paid_minutes_used" do
    test "includes macos 12-core" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: @user.plan.actions_included_private_minutes + 100,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos",
            },
            usage: {
              estimated_cost: { subunits: 500.0 },
              effective_quantity: 500.0,
            }
          },
          {
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos_12_core",
            },
            usage: {
              estimated_cost: { subunits: 200.0 },
              effective_quantity: 200.0,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user)
      expected_usage = 800

      assert_equal(expected_usage, actions_usage.total_paid_minutes_used)
    end
  end

  context "#used_up_entitlements?" do
    test "returns true when the user has used up all their entitlements" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: @user.plan.actions_included_private_minutes + 100
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert_equal(true, actions_usage.used_up_entitlements?)
    end

    test "ignores macos 12-core usage" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 0,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "macos_12_core",
            },
            usage: {
              estimated_cost: { subunits: @user.plan.actions_included_private_minutes + 100 },
              effective_quantity: @user.plan.actions_included_private_minutes + 100,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert_equal(false, actions_usage.used_up_entitlements?)
    end

    test "ignores custom runner usage" do
      mock_list_product_usage_response(
        product: "actions",
        sku_name: "linux",
        unit_of_measure: "Hours",
        quantity: 0,
        additional_product_usages:
          [{
            product: {
              name: "actions"
            },
            product_sku: {
              name: "linux_4_core",
            },
            usage: {
              estimated_cost: { subunits: @user.plan.actions_included_private_minutes + 100 },
              effective_quantity: @user.plan.actions_included_private_minutes + 100,
            }
          }]
      )

      actions_usage = ::Billing::ActionsUsage.product_usage(@user)

      assert_equal(false, actions_usage.used_up_entitlements?)
    end
  end

end if GitHub.billing_enabled?
