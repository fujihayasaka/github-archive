# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredUsageReportGeneratorTest < GitHub::BillingTestCase
  include ::Billing::ApiTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:organization)
    @codespaces_eligible_owner = create(:business_plus_org)
    @repo = create(:repository, owner: @owner, from_example: :repository_test_simple)
    @package = create(:registry_package, owner: @owner, repository: @repo)
    @business = create(:business)
    @org1 = create(:organization, business: @business)
    @org2 = create(:organization, business: @business)
    @user = create(:user)
    @email = create(:user_email, user: @user, email: "some_email@example.com")
    @staff_user = create(:staff_admin_user)
    @staff_email = create(:user_email, user: @staff_user, email: "staff_user@github.com")
    @emu = create(:emu, :owner, email: "owner@example.com")
    @emu_business = @emu.enterprise_managed_business
  end

  setup do
    mock_get_usage_line_items_response_without_usage
  end

  context "#to_csv" do
    context "handles formatting" do
      test "for all products" do
        @business.customer.update! metered_ghe: "true"

        # Actions
        codespace_workflow = create(:workflow, repository: @repo,
          name: Codespaces::Prebuilds::WORKFLOW_NAME,
          path: "dynamic/#{Apps::Internal::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}/#{Codespaces::Prebuilds::WORKFLOW_SLUG}")
        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 1,
              product_sku_name: "linux",
              multiplier: 1,
              rate_plan_unit_price: 0.008,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 9.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": codespace_workflow.id.to_s,
              },
            ),
          ],
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions] }
        )

        # Packages
        package = create(:registry_package, owner: @owner, repository: @repo)
        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 512.megabytes,
              product_id: 2,
              product_sku_name: "default",
              multiplier: 1,
              rate_plan_unit_price: 0.5,
              usage_at: Google::Protobuf::Timestamp.new(seconds:  9.days.ago.to_i),
              custom_fields: {
                "package.id": package.id.to_s,
              },
            ),
          ],
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:packages] }
        )

        # Shared storage
        today_beginning_of_day = GitHub::Billing.timezone.parse(GitHub::Billing.today.to_s).beginning_of_day.to_i
        today_end_of_day = GitHub::Billing.timezone.parse(GitHub::Billing.today.to_s).end_of_day.to_i
        mock_get_usage_line_items_response_with(
          usage_line_items: (today_beginning_of_day..today_end_of_day).step(1.hour).map do |date|
            create_mock_usage_line_item(
              repository_id: @repo.id,
              product_sku_name: "default",
              quantity: Time.at(date).hour.even? ? 512.megabytes : 2.gigabytes,
              multiplier: 1,
              rate_plan_unit_price: 3.28e-07,
              usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
            )
          end,
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:shared_storage] }
        )

        # Codespaces
        create(:business_plus_org, business: @business)
        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 10.1234971234,
              product_id: 4,
              multiplier: 1,
              rate_plan_unit_price: 0.25,
              product_sku_name: "storage",
              usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
              custom_fields: {},
            ),
          ],
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:codespaces] }
        )

        # CFB
        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              quantity: 0.032258064,
              product_id: 5,
              multiplier: 1,
              rate_plan_unit_price: 0.19e2,
              product_sku_name: "copilot_for_business",
              usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
              custom_fields: {},
            ),
          ],
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot] }
        )

        # GHEC
        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              quantity: 0.032258064,
              product_id: 5,
              multiplier: 1,
              rate_plan_unit_price: 0.19e2,
              product_sku_name: "seats",
              usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
            ),
          ],
          times: 2,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:ghec] }
        )

        Billing::MeteredUsageReportGenerator.new(@business, start_date: ::GitHub::Billing.today - 9.days).to_csv.split("\n")

        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:actions"])
        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:packages"])
        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:shared_storage"])
        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:codespaces"])
        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:copilot"])
        assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:ghec"])
      end

      test "for Actions" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          codespace_workflow = create(:workflow, repository: @repo,
            name: Codespaces::Prebuilds::WORKFLOW_NAME,
            path: "dynamic/#{Apps::Internal::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}/#{Codespaces::Prebuilds::WORKFLOW_SLUG}")

          dependabot_security_workflow = create(:workflow, repository: @repo,
            name: "Dependabot Security Updates",
            path: "dynamic/dependabot/dependabot-security-updates")

          dependabot_version_workflow = create(:workflow, repository: @repo,
            name: "Dependabot Version Updates",
            path: "dynamic/dependabot/dependabot-version-updates")

          dynamic_workflow = create(:workflow, repository: @repo,
            name: "Some Dynamic Workflow",
            path: "dynamic/some-integration/some-slug")

          mock_get_usage_line_items_response_with(usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 1,
              product_sku_name: "linux",
              multiplier: 1,
              rate_plan_unit_price: 0.008,
              owner_id: @repo.owner.id,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 9.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": codespace_workflow.id.to_s,
              },
            ),
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 1,
              product_sku_name: "linux",
              multiplier: 1,
              rate_plan_unit_price: 0.008,
              owner_id: @repo.owner.id,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 8.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": dependabot_security_workflow.id.to_s,
              },
            ),
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 2,
              product_sku_name: "windows",
              multiplier: 2,
              rate_plan_unit_price: 0.008,
              owner_id: @repo.owner.id,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 7.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": dependabot_version_workflow.id.to_s,
              },
            ),
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 2,
              product_sku_name: "windows",
              multiplier: 2,
              rate_plan_unit_price: 0.008,
              owner_id: @repo.owner.id,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 6.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": dynamic_workflow.id.to_s,
              },
            ),
          ], times: 2, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions] })

          report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 9.days, products: ["actions"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-11,Actions,Compute - UBUNTU,1,minute,0.008,1.0,#{@repo.owner.login},#{@repo.name},,#{Codespaces::Prebuilds::WORKFLOW_SLUG.titleize},"
          assert_includes report, "2019-11-12,Actions,Compute - UBUNTU,1,minute,0.008,1.0,#{@repo.owner.login},#{@repo.name},,Dependabot Security Updates,"
          assert_includes report, "2019-11-13,Actions,Compute - WINDOWS,2,minute,0.016,2.0,#{@repo.owner.login},#{@repo.name},,Dependabot Version Updates,"
          assert_includes report, "2019-11-14,Actions,Compute - WINDOWS,2,minute,0.016,2.0,#{@repo.owner.login},#{@repo.name},,Some Integration - Some Slug,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:actions"])
        end
      end

      test "for Packages" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          package = create(:registry_package, owner: @owner, repository: @repo)

          mock_get_usage_line_items_response_with(usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 512.megabytes,
              product_id: 2,
              product_sku_name: "default",
              multiplier: 1,
              rate_plan_unit_price: 0.5,
              usage_at: Google::Protobuf::Timestamp.new(seconds:  9.days.ago.to_i),
              custom_fields: {
                "package.id": package.id.to_s,
              },
            ),
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 512.megabytes,
              product_id: 2,
              product_sku_name: "default",
              multiplier: 1,
              rate_plan_unit_price: 0.5,
              usage_at: Google::Protobuf::Timestamp.new(seconds:  8.days.ago.to_i),
              custom_fields: {
                "package.id": package.id.to_s,
              },
            ),
          ], times: 2, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:packages] })


          report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 9.days, products: ["packages"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-11,Packages,Data Transfer,0.5,gb,0.50,1.0,,#{@repo.name},,,"
          assert_includes report, "2019-11-12,Packages,Data Transfer,0.5,gb,0.50,1.0,,#{@repo.name},,,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:packages"])
        end
      end

      test "for Shared Storage" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          three_days_ago_beginning_of_day = 3.days.ago.in_billing_timezone.beginning_of_day.to_i
          three_days_ago_end_of_day = 3.days.ago.in_billing_timezone.end_of_day.to_i
          usage_line_items_3_days_ago = (three_days_ago_beginning_of_day..three_days_ago_end_of_day).step(1.hour).map do |date|
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 3.gigabytes,
              multiplier: 1,
              rate_plan_unit_price: 3.28e-07,
              usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
            )
          end

          today_beginning_of_day = GitHub::Billing.timezone.parse(GitHub::Billing.today.to_s).beginning_of_day.to_i
          today_end_of_day = GitHub::Billing.timezone.parse(GitHub::Billing.today.to_s).end_of_day.to_i
          usage_line_items_today = (today_beginning_of_day..today_end_of_day).step(1.hour).map do |date|
            create_mock_usage_line_item(
              repository_id: @repo.id,
              product_sku_name: "default",
              quantity: Time.at(date).hour.even? ? 512.megabytes : 2.gigabytes,
              multiplier: 1,
              rate_plan_unit_price: 3.28e-07,
              usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
            )
          end

          # This represents shared storage usage from a repository that was deleted
          # Since there are no further line items associated to this repository after deletion,
          # the quantity (24) will be divided by 24, resulting in a daily average usage of 1gb
          deleted_repository = create(:repository, owner: @owner)
          deleted_repository_usage = [create_mock_usage_line_item(
            repository_id: deleted_repository.id,
            product_sku_name: "default",
            quantity: 24.gigabytes,
            multiplier: 1,
            rate_plan_unit_price: 3.28e-07,
            usage_at: Google::Protobuf::Timestamp.new(seconds: three_days_ago_beginning_of_day)
          )]
          deleted_repository.destroy!

          mock_get_usage_line_items_response_with(
            usage_line_items: usage_line_items_3_days_ago + usage_line_items_today + deleted_repository_usage,
            times: 2,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:shared_storage] }
          )

          report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 9.days, products: ["shared_storage"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-17,Shared Storage,Shared Storage,3.0,gb-day,0.008,1.0,,#{@repo.name},,,"
          assert_includes report, "2019-11-20,Shared Storage,Shared Storage,1.25,gb-day,0.008,1.0,,#{@repo.name},,,"
          assert_includes report, "2019-11-17,Shared Storage,Shared Storage,1.0,gb-day,0.008,1.0,,deleted repositories,,,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:shared_storage"])
        end
      end

      test "for Codespaces" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          mock_get_usage_line_items_response_with(
            usage_line_items: [
              create_mock_usage_line_item(
                repository_id: @repo.id,
                quantity: 10.1234971234,
                product_id: 4,
                multiplier: 1,
                rate_plan_unit_price: 0.25,
                product_sku_name: "storage",
                owner_id: @owner.id,
                actor_id: @user.id,
                usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
                custom_fields: {},
              ),
              create_mock_usage_line_item(
                repository_id: @repo.id,
                quantity: 1000,
                product_id: 4,
                multiplier: 1,
                rate_plan_unit_price: 0.25,
                product_sku_name: "compute_d4",
                owner_id: @owner.id,
                actor_id: @user.id,
                usage_at: Google::Protobuf::Timestamp.new(seconds:  2.days.ago.to_i),
                custom_fields: {},
              ),
            ],
            times: 2,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:codespaces] }
          )

          report = Billing::MeteredUsageReportGenerator.new(@codespaces_eligible_owner, start_date: ::GitHub::Billing.today - 9.days, products: ["codespaces"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-17,Codespaces - Linux,Storage,10.1235,gb-month,0.25,1.0,#{@owner.login},#{@repo.name},#{@user.login},,"
          assert_includes report, "2019-11-18,Codespaces - Linux,Compute - 4 core,1000.0,hour,0.25,1.0,#{@owner.login},#{@repo.name},#{@user.login},,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:codespaces"])
        end
      end

      test "for Copilot Business" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          mock_get_usage_line_items_response_with(
            usage_line_items: [
              create_mock_usage_line_item(
                quantity: 0.032258064,
                product_id: 5,
                multiplier: 1,
                rate_plan_unit_price: 0.19e2,
                product_sku_name: "copilot_for_business",
                owner_id: @owner.id,
                actor_id: @user.id,
                usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
                custom_fields: {},
              ),
            ],
            times: 2,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot] }
          )

          report = Billing::MeteredUsageReportGenerator.new(@business, start_date: ::GitHub::Billing.today - 9.days, products: ["copilot_for_business"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-17,Copilot,Copilot Business,0.0323,user-month,19.0,1.0,#{@owner.login},,#{@user.login},,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:copilot"])
        end
      end

      test "metered GHEC" do
        @business.customer.update! metered_ghe: "true"
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          mock_get_usage_line_items_response_with(
            usage_line_items: [
              create_mock_usage_line_item(
                quantity: 0.032258064,
                product_id: 5,
                multiplier: 1,
                rate_plan_unit_price: 0.19e2,
                product_sku_name: "seats",
                usage_at: Google::Protobuf::Timestamp.new(seconds:  3.days.ago.to_i),
              ),
            ],
            times: 2,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:ghec] }
          )

          report = Billing::MeteredUsageReportGenerator.new(@business, start_date: ::GitHub::Billing.today - 9.days, products: ["ghec"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-17,GHEC,Seats,0.0323,user-month,19.0,1.0,,,,,"

          assert_dogstats_distribution(2, "billing.usage_report", tags: ["product:ghec"])
        end
      end

      test "for businesses without metered ghec" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          report = Billing::MeteredUsageReportGenerator.new(@business, start_date: ::GitHub::Billing.today - 9.days, products: ["ghec"]).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_nil report[1]

          assert_dogstats_distribution(0, "billing.usage_report", tags: ["product:ghec"])
        end
      end

      test "for business-owned orgs" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          business = create(:business)
          org = create(:organization)
          repo1 = create(:repository, owner: org)
          repo2 = create(:repository, owner: org)
          business.add_organization(org)
          org = Organization.find(org.id)

          codespace_workflow = create(:workflow, repository: repo1,
            name: Codespaces::Prebuilds::WORKFLOW_NAME,
            path: "dynamic/#{Apps::Internal::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}/#{Codespaces::Prebuilds::WORKFLOW_SLUG}")

          dependabot_security_workflow = create(:workflow, repository: repo2,
            name: "Dependabot Security Updates",
            path: "dynamic/dependabot/dependabot-security-updates")

          # Expect each invokation 5 times due to smaller batch size for business-owned orgs
          mock_get_usage_line_items_response_with(usage_line_items: [
            create_mock_usage_line_item(
              owner_id: org.id,
              repository_id: repo1.id,
              quantity: 1,
              product_sku_name: "linux",
              multiplier: 1,
              rate_plan_unit_price: 0.008,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 9.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": codespace_workflow.id.to_s,
              },
            ),
            create_mock_usage_line_item(
              owner_id: org.id,
              repository_id: repo2.id,
              quantity: 1,
              product_sku_name: "linux",
              multiplier: 1,
              rate_plan_unit_price: 0.008,
              usage_at: Google::Protobuf::Timestamp.new(seconds: 8.days.ago.to_i),
              custom_fields: {
                "actions.workflow.id": dependabot_security_workflow.id.to_s,
              },
            ),
          ], times: 5, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions] })

          report = Billing::MeteredUsageReportGenerator.new(org, start_date: ::GitHub::Billing.today - 9.days).to_csv.split("\n")

          assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
          assert_includes report, "2019-11-11,Actions,Compute - UBUNTU,1,minute,0.008,1.0,#{org.login},#{repo1.name},,#{Codespaces::Prebuilds::WORKFLOW_SLUG.titleize},"
          assert_includes report, "2019-11-12,Actions,Compute - UBUNTU,1,minute,0.008,1.0,#{org.login},#{repo2.name},,Dependabot Security Updates,"

          assert_dogstats_distribution(5, "billing.usage_report", tags: ["product:codespaces"])
        end
      end

      test "does not query meuse for codespaces usage when the billable_owner does not have codespaces billing enabled" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          # The query for Codespaces should not be made
          mock_get_usage_line_items_response_with(
            usage_line_items: [],
            times: 0,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:codespaces] }
          )

          # The query for Copilot should not be made
          mock_get_usage_line_items_response_with(
            usage_line_items: [],
            times: 0,
            required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot] }
          )

          report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 9.days).to_csv.split("\n")
          assert_equal report, ["Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"]
        end
      end
    end

    test "merges packages belonging to the same repo by date" do
      travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
        other_package = create(:registry_package, owner: @owner, repository: @repo)

        mock_get_usage_line_items_response_with(usage_line_items: [
          create_mock_usage_line_item(
            repository_id: @repo.id,
            quantity: 512.megabytes,
            product_id: 2,
            product_sku_name: "default",
            multiplier: 1,
            rate_plan_unit_price: 0.5,
            owner_id: @repo.owner.id,
            usage_at: Google::Protobuf::Timestamp.new(seconds:  1.day.ago.to_i),
            custom_fields: {
              "package.id": @package.id.to_s,
            },
          ),
          create_mock_usage_line_item(
            repository_id: @repo.id,
            quantity: 512.megabytes,
            product_id: 2,
            product_sku_name: "default",
            multiplier: 1,
            rate_plan_unit_price: 0.5,
            owner_id: @repo.owner.id,
            usage_at: Google::Protobuf::Timestamp.new(seconds:  1.day.ago.to_i),
            custom_fields: {
              "package.id": other_package.id.to_s,
            },
          ),
          create_mock_usage_line_item(
            repository_id: @repo.id,
            quantity: 512.megabytes,
            product_id: 2,
            product_sku_name: "default",
            multiplier: 1,
            rate_plan_unit_price: 0.5,
            owner_id: @repo.owner.id,
            usage_at: Google::Protobuf::Timestamp.new(seconds:  2.days.ago.to_i),
            custom_fields: {
              "package.id": @package.id.to_s,
            },
          ),
        ], times: 2, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:packages] })

        report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 9.days).to_csv.split("\n")

        assert_equal report[0], "Date,Product,SKU,Quantity,Unit Type,Price Per Unit ($),Multiplier,Owner,Repository Slug,Username,Actions Workflow,Notes"
        assert_includes report, "2019-11-18,Packages,Data Transfer,0.5,gb,0.50,1.0,#{@repo.owner.login},#{@repo.name},,,"
        assert_includes report, "2019-11-19,Packages,Data Transfer,1.0,gb,0.50,1.0,#{@repo.owner.login},#{@repo.name},,,"
      end
    end

    test "handles deleted repositories gracefully" do
      travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
        codespace_workflow = create(:workflow, repository: @repo,
          name: Codespaces::Prebuilds::WORKFLOW_NAME,
          path: "dynamic/#{Apps::Internal::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}/#{Codespaces::Prebuilds::WORKFLOW_SLUG}"
        )

        mock_get_usage_line_items_response_with(usage_line_items: [
          create_mock_usage_line_item(
            repository_id: @repo.id,
            quantity: 1,
            product_sku_name: "linux",
            multiplier: 1,
            rate_plan_unit_price: 0.008,
            usage_at: Google::Protobuf::Timestamp.new(seconds: 4.days.ago.to_i),
            custom_fields: {
              "actions.workflow.id": codespace_workflow.id.to_s,
            },
          ),
        ], times: 1, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions] })

        mock_get_usage_line_items_response_with(
          usage_line_items: [
            create_mock_usage_line_item(
              repository_id: @repo.id,
              quantity: 24.gigabyte,
              product_sku_name: "default",
              multiplier: 1,
              rate_plan_unit_price: 3.28e-07,
              usage_at: Google::Protobuf::Timestamp.new(seconds:  (4.days.ago).to_i),
            ),
          ],
          times: 1,
          required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:shared_storage] }
        )

        @repo.destroy

        report = Billing::MeteredUsageReportGenerator.new(@owner, start_date: ::GitHub::Billing.today - 5.days).to_csv.split("\n")

        assert_includes report, "2019-11-16,Actions,Compute - UBUNTU,1,minute,0.008,1.0,,deleted repositories,,Create Codespaces Prebuilds,"
        assert_includes report, "2019-11-16,Shared Storage,Shared Storage,1.0,gb-day,0.008,1.0,,deleted repositories,,,"
      end
    end

    context "properly handles timezone selection based on user's billing plan" do
      test "uses UTC timezone when the billable owner is billed through azure" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          azure_business = create(:business, :with_azure_subscription)

          date_to_convert = GitHub::Billing.timezone.parse(GitHub::Billing.today.to_s)

          metered_usage_report_generator = Billing::MeteredUsageReportGenerator.new(azure_business, start_date: GitHub::Billing.today - 5.days, end_date: date_to_convert)
          time_based_on_billing_timezone = metered_usage_report_generator.send(:convert_to_billed_timezone, date_to_convert)

          assert_equal time_based_on_billing_timezone.zone, "UTC"
          assert_equal time_based_on_billing_timezone, "Wed, 20 Nov 2019 08:00:00.000000000 UTC +00:0"
        end
      end

      test "uses Pacific timezone when the billable owner is billed through zuora" do
        travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
          zuora_business = create(:organization, :zuora)

          date_to_convert = Time.now.utc

          metered_usage_report_generator = Billing::MeteredUsageReportGenerator.new(zuora_business, start_date: GitHub::Billing.today - 5.days, end_date: date_to_convert)
          time_based_on_billing_timezone = metered_usage_report_generator.send(:convert_to_billed_timezone, date_to_convert)

          assert_equal time_based_on_billing_timezone.zone, "PST"
          assert_equal time_based_on_billing_timezone, "Wed, 20 Nov 2019 02:00:00.000000000 PST -08:00"
        end
      end
    end
  end

  context "#email_for_export" do
    test "generates correct email for export for individual user" do
      @user.set_primary_email!(@email)

      assert_equal "some_email@example.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @user, target: @user)
    end

    test "generates correct email for export for individual user with private email" do
      @user.set_primary_email!(@email)
      @user.primary_user_email.toggle_visibility

      assert_equal "some_email@example.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @user, target: @user)
    end

    test "generates correct email for export for an enterprise managed user (EMU)" do
      export_email = Billing::MeteredUsageReportGenerator.email_for_export \
        requester: @emu,
        target: @emu_business

      assert_equal @emu.profile_email, export_email
      refute_equal @emu.email, export_email
    end

    test "generates correct email for export for user of an organization" do
      @org1.billing.add_manager(@user, actor: @user)

      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org1, "some_email@example.com")
      end

      assert_equal "some_email@example.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @user, target: @org1)
    end

    test "generates correct email for export for user of a business" do
      @org1.billing.add_manager(@user, actor: @user)
      @org2.billing.add_manager(@user, actor: @user)

      create(:user_email, user: @user, email: "some_wrong_email@example.com")

      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org1, "some_email@example.com")
        settings.email(@org2, "some_wrong_email@example.com")
      end

      assert_equal "some_email@example.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @user, target: @business)
    end

    test "generates correct email for export for user of a business with no orgs" do
      @user.set_primary_email!(@email)

      business_with_no_orgs = create(:business)
      business_with_no_orgs.add_owner(@user, actor: @user)

      assert_equal "some_email@example.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @user, target: business_with_no_orgs)
    end

    test "generates the correct verified email for orgs with verified emails" do
      create :verifiable_domain, owner: @org1, domain: "my-org.com", verified: true
      @org1.enable_notification_restrictions(actor: @user, force: true)

      @org1.add_member(@user)
      @org1.billing.add_manager(@user, actor: @user)

      org_verified_email = create :user_email, :verified, user: @user, email: "test@my-org.com"

      export_email = Billing::MeteredUsageReportGenerator.email_for_export \
        requester: @user,
        target: @org1.reload

      assert_equal org_verified_email.email, export_email
    end

    test "generates the correct verified email for a business with verified emails" do
      create :verifiable_domain, owner: @business, domain: "my-org.com", verified: true
      @business.enable_notification_restrictions(actor: @user, force: true)

      @org1.add_member(@user)
      @org1.billing.add_manager(@user, actor: @user)

      org_verified_email = create :user_email, :verified, user: @user, email: "test@my-org.com"

      export_email = Billing::MeteredUsageReportGenerator.email_for_export \
        requester: @user,
        target: @business.reload

      assert_equal org_verified_email.email, export_email
    end

    test "generates correct email when requested by staff for an individual user" do
      @staff_user.set_primary_email!(@staff_email)
      @user.set_primary_email!(@email)

      assert_equal "staff_user@github.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @staff_user, target: @user)
    end

    test "generates correct email when requested by staff for an organization they do not belong to" do
      @staff_user.set_primary_email!(@staff_email)
      @org1.billing.add_manager(@user, actor: @user)

      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org1, "some_email@example.com")
      end

      assert_equal "staff_user@github.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @staff_user, target: @org1)
    end

    test "generates correct email when requested by staff for a business they do not belong to" do
      @staff_user.set_primary_email!(@staff_email)

      @org1.billing.add_manager(@user, actor: @user)
      @org2.billing.add_manager(@user, actor: @user)

      create(:user_email, user: @user, email: "some_wrong_email@example.com")

      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org1, "some_email@example.com")
        settings.email(@org2, "some_wrong_email@example.com")
      end

      assert_equal "staff_user@github.com", Billing::MeteredUsageReportGenerator.email_for_export(requester: @staff_user, target: @business)
    end

    test "generates correct email when requested by staff for an organization they belong to with verified emails" do
      @staff_user.set_primary_email!(@staff_email)

      create :verifiable_domain, owner: @org1, domain: "my-org.com", verified: true
      @org1.enable_notification_restrictions(actor: @staff_user, force: true)

      @org1.add_member(@staff_user)
      @org1.billing.add_manager(@staff_user, actor: @staff_user)

      org_verified_email = create :user_email, :verified, user: @staff_user, email: "staff_user@my-org.com"

      export_email = Billing::MeteredUsageReportGenerator.email_for_export \
        requester: @staff_user,
        target: @org1.reload

      assert_equal org_verified_email.email, export_email
    end
  end
end
