# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::HostedPaymentsPageTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @user = create(:user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context ".params" do
    test "returns payments page params for user" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
      ).params

      expected_gateway = ::Billing::Zuora::PaymentGateway.for(@user, type: :credit_card)

      params_expected = {
        id: "2c92c0f961ff2cf401620272b4fc439f",
        key: "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmRe6W/vWgKj2Qede+NvFJaILUtFWbpiK1obzVqadfDOq3o6VRddQMTlXDFCrAWyIFJWEcMnZz+eQ0pvLo/Y8zhkVJMLnmg+5uaGH+7dwF8Jx/Y8DYBZrt7EUjueJhMsO9Z76aN5QZiJq8d//HGEEjbbIoge/b7QMOA7sg3P6+Vx0c9o1yYTBta0cVSnyn9QCBJxyoEpu9ry4aZJiuHxSzHc34BWidAcaBjlSr7f9pkePBdZbhaI/+t5z9j6hN7MhZy58iNNSrOoxA4fMhP7SYvxOXYc5E84/Rjd2QvwfKYScbCpXATTNC9FvXs9lde5LsM1RljRbxV2eK1fPea8VWwIDAQAB",
        signature: "HOQo+v07EHMNvHpby7f458sUC2ZdfoDZGjtylmPF/vaWepAAN0kkkzr9jA0AmwmXUrC8tmbmTVlBSC2UOt6o6NrkyK5wvovQsXIK5mo3zbbv3Pgq2kWtrtnLVEw850boaEqTQq1EbimMoDHo+R8iuGwUCZbXe9+GZcGOkD7DWPbRIfeBllkZVfCE8ecsETMB7oCAn1VAsnMUQQOrU6sC8nqwrRmXMLFM2h6Df70DaZwEVGxze3SNGnQreJwhF0vIPgpLI3zTeWd3VNIQTouVfPMhAvquSUW7J5Z2fD9uS41/9tiUxIlqDVHLVpjp1uAsDKzptZZwKEluomBZe1IYdA==",
        tenantId: "15907",
        token: "kzxphj0ABjaJtAsjmvsJ8vYzj9Yvn2W9",
        url: "https://apisandbox.zuora.com/apps/PublicHostedPageLite.do",
        countryBlackList: %w[CUB PRK SYR],
        paymentGateway: expected_gateway,
        style: "inline",
        submitEnabled: "true",
        doPayment: false
      }

      assert_equal params_expected, params
    end

    test "returns payments page params for organization" do
      org = create(:organization)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: org,
      ).params

      expected_gateway = ::Billing::Zuora::PaymentGateway.for(org, type: :credit_card)

      params_expected = {
        id: "2c92c0f961ff2cf401620272b4fc439f",
        key: "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmRe6W/vWgKj2Qede+NvFJaILUtFWbpiK1obzVqadfDOq3o6VRddQMTlXDFCrAWyIFJWEcMnZz+eQ0pvLo/Y8zhkVJMLnmg+5uaGH+7dwF8Jx/Y8DYBZrt7EUjueJhMsO9Z76aN5QZiJq8d//HGEEjbbIoge/b7QMOA7sg3P6+Vx0c9o1yYTBta0cVSnyn9QCBJxyoEpu9ry4aZJiuHxSzHc34BWidAcaBjlSr7f9pkePBdZbhaI/+t5z9j6hN7MhZy58iNNSrOoxA4fMhP7SYvxOXYc5E84/Rjd2QvwfKYScbCpXATTNC9FvXs9lde5LsM1RljRbxV2eK1fPea8VWwIDAQAB",
        signature: "HOQo+v07EHMNvHpby7f458sUC2ZdfoDZGjtylmPF/vaWepAAN0kkkzr9jA0AmwmXUrC8tmbmTVlBSC2UOt6o6NrkyK5wvovQsXIK5mo3zbbv3Pgq2kWtrtnLVEw850boaEqTQq1EbimMoDHo+R8iuGwUCZbXe9+GZcGOkD7DWPbRIfeBllkZVfCE8ecsETMB7oCAn1VAsnMUQQOrU6sC8nqwrRmXMLFM2h6Df70DaZwEVGxze3SNGnQreJwhF0vIPgpLI3zTeWd3VNIQTouVfPMhAvquSUW7J5Z2fD9uS41/9tiUxIlqDVHLVpjp1uAsDKzptZZwKEluomBZe1IYdA==",
        tenantId: "15907",
        token: "kzxphj0ABjaJtAsjmvsJ8vYzj9Yvn2W9",
        url: "https://apisandbox.zuora.com/apps/PublicHostedPageLite.do",
        countryBlackList: %w[CUB PRK SYR],
        paymentGateway: expected_gateway,
        style: "inline",
        submitEnabled: "true",
        doPayment: false
      }

      assert_equal params_expected, params
    end

    test "returns payments page params for enterprise" do
      enterprise = create(:business)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: enterprise,
      ).params

      expected_gateway = ::Billing::Zuora::PaymentGateway.for(enterprise, type: :credit_card)

      params_expected = {
        id: "2c92c0f961ff2cf401620272b4fc439f",
        key: "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmRe6W/vWgKj2Qede+NvFJaILUtFWbpiK1obzVqadfDOq3o6VRddQMTlXDFCrAWyIFJWEcMnZz+eQ0pvLo/Y8zhkVJMLnmg+5uaGH+7dwF8Jx/Y8DYBZrt7EUjueJhMsO9Z76aN5QZiJq8d//HGEEjbbIoge/b7QMOA7sg3P6+Vx0c9o1yYTBta0cVSnyn9QCBJxyoEpu9ry4aZJiuHxSzHc34BWidAcaBjlSr7f9pkePBdZbhaI/+t5z9j6hN7MhZy58iNNSrOoxA4fMhP7SYvxOXYc5E84/Rjd2QvwfKYScbCpXATTNC9FvXs9lde5LsM1RljRbxV2eK1fPea8VWwIDAQAB",
        signature: "HOQo+v07EHMNvHpby7f458sUC2ZdfoDZGjtylmPF/vaWepAAN0kkkzr9jA0AmwmXUrC8tmbmTVlBSC2UOt6o6NrkyK5wvovQsXIK5mo3zbbv3Pgq2kWtrtnLVEw850boaEqTQq1EbimMoDHo+R8iuGwUCZbXe9+GZcGOkD7DWPbRIfeBllkZVfCE8ecsETMB7oCAn1VAsnMUQQOrU6sC8nqwrRmXMLFM2h6Df70DaZwEVGxze3SNGnQreJwhF0vIPgpLI3zTeWd3VNIQTouVfPMhAvquSUW7J5Z2fD9uS41/9tiUxIlqDVHLVpjp1uAsDKzptZZwKEluomBZe1IYdA==",
        tenantId: "15907",
        token: "kzxphj0ABjaJtAsjmvsJ8vYzj9Yvn2W9",
        url: "https://apisandbox.zuora.com/apps/PublicHostedPageLite.do",
        countryBlackList: %w[CUB PRK SYR],
        paymentGateway: expected_gateway,
        style: "inline",
        submitEnabled: "true",
        doPayment: false
      }

      assert_equal params_expected, params
    end

    test "returns error when the target user is spammy" do
      spammy_user = create(:spammy_user)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: spammy_user,
      ).params

      assert_equal Billing::Zuora::HostedPaymentsPage::SPAMMY_MESSAGE, params[:error]
    end

    test "returns error when the target user has trade restrictions" do
      trade_restricted_user = create(:user, :fully_trade_restricted)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: trade_restricted_user,
      ).params

      assert_equal TradeControls::Notices.notice_as_plaintext(:user_account_restricted), params[:error]
    end

    test "returns error when the RSA signature cannot be generated" do
      user = create(:user)

      stub_request(:post, "#{GitHub.zuora_rest_server}/v1/rsa-signatures").to_timeout

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: user,
      ).params

      assert_equal Billing::Zuora::HostedPaymentsPage::RSA_SIGNATURE_GENERATION_ERROR, params[:error]
    end

    test "prefills development credit card when in the development environment" do
      Rails.env.stubs(:development?).returns(true)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
      ).params

      assert_equal "Mona Lisa", params[:prepopulate][:creditCardHolderName]
    end

    test "does not prefill development credit card when not in the development environment" do
      Rails.env.stubs(:development?).returns(false)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
      ).params

      refute params[:prepopulate].present?
    end

    test "prefills credit card for user with trade screening record" do
      user_with_trade_screening_record = create(:user, :with_trade_screening_record)
      card_holder_name = user_with_trade_screening_record.trade_screening_record.fullname

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: user_with_trade_screening_record,
      ).params

      assert_equal card_holder_name, params[:prepopulate][:creditCardHolderName]
    end

    test "returns account ID if provided" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
        account_id: "123",
      ).params

      assert_equal "123", params[:field_accountId]
    end

    test "returns invoices when manual payment" do
      enterprise = create(:business)

      Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
        create(:zuora_invoice, amount: 100, invoiceNumber: "INV-1")
      ])

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: enterprise,
        manual_payment: true,
      ).params

      assert_equal true, params[:doPayment]
      assert_equal "[{\"type\":\"invoice\",\"ref\":\"INV-1\"}]", params[:documents]
    end

    test "returns passed invoices to collect for manual payment" do
      create(:customer, :zuora, payment_method_user: @user, customer_account_user: @user)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
        manual_payment: true,
        invoices: %w[INV001 INV002]
      ).params

      expected_invoice_params = [
        { type: "invoice", ref: "INV001" },
        { type: "invoice", ref: "INV002" },
      ].to_json

      assert_equal true, params[:doPayment]
      assert_equal expected_invoice_params, params[:documents]
    end

    test "returns passed payment gatewy" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
        payment_gateway: "some gateway",
      ).params

      assert_equal "some gateway", params[:paymentGateway]
    end

    # This test codifies the current behavior that is not ideal
    # In production, user entering the manual payment flow is pretty much guranteed to have a Zuora account
    # In the future we could either return the "error" response or silently ignore
    test "raises an error when manual payment for user with no zuora account" do
      assert_raises(TypeError, "Passed `nil` into T.must") do
        Billing::Zuora::HostedPaymentsPage.new(
          page_name: :settings_regular,
          target: @user,
          manual_payment: true,
        ).params
      end
    end

    test "applies specified color theme if available for given page" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_compact,
        target: @user,
        color_theme: ColorMode::DARK,
      ).params

      assert_equal GitHub.zuora_settings_compact_dark_default_payment_page_id, params[:id]
    end

    test "applies default color theme if specified theme not available for given page" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :invoices,
        target: @user,
        color_theme: ColorMode::DARK,
      ).params

      assert_equal GitHub.zuora_invoices_light_default_payment_page_id, params[:id]
    end

    test "applies default color theme if no theme specified" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :invoices,
        target: @user,
      ).params

      assert_equal GitHub.zuora_invoices_light_default_payment_page_id, params[:id]
    end

    test "raises ArgumentError if page_name is not valid" do
      assert_raises(ArgumentError) do
        Billing::Zuora::HostedPaymentsPage.new(
          page_name: :invalid_page_name,
          target: @user,
        ).params
      end
    end

    test "returns default page ID when running on github.com host" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :sign_up,
        target: @user,
        host: "github.com",
      ).params

      assert_equal GitHub.zuora_sign_up_light_default_payment_page_id, params[:id]
    end

    test "returns preview page ID when running on githubpreview.dev host" do
      Rails.env.stubs(:development?).returns(true)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :sign_up,
        target: @user,
        host: "monalisa-github-github-p6jx4r5jx39pq6-80.githubpreview.dev",
      ).params

      assert_equal GitHub.zuora_sign_up_light_preview_payment_page_id, params[:id]
    end

    test "returns default page ID when running on githubpreview.dev host but not in development environment" do
      Rails.env.stubs(:development?).returns(false)

      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :sign_up,
        target: @user,
        host: "monalisa-github-github-p6jx4r5jx39pq6-80.githubpreview.dev",
      ).params

      assert_equal GitHub.zuora_sign_up_light_default_payment_page_id, params[:id]
    end

    test "track via stats" do
      params = Billing::Zuora::HostedPaymentsPage.new(
        page_name: :settings_regular,
        target: @user,
        color_theme: ColorMode::DARK,
        host: "github.com",
      ).params

      tags_expected = [
        "page_name:settings_regular",
        "color_theme:dark",
        "host:github.com",
      ]

      assert_equal 1, GitHub.dogstats.increments("billing.hosted_payment_page", tags: tags_expected).count
    end
  end
end
