# typed: strict
# frozen_string_literal: true

require "zip"

class BillingSettings::InvoicesDownloadController < ApplicationController
  include GitHub::RateLimitedRequest

  rate_limit_requests(max: 100, ttl: 1.hour, key: :invoice_download_rate_limit_key, at_limit: :invoice_download_rate_limit_at_limit)

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_account_exists
  before_action :ensure_account_manageable_by_user
  before_action :ensure_transaction_exists

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  sig { void }
  def show
    begin
      start_time = GitHub::Dogstats.monotonic_time
      invoice_download_success = T.let(false, T::Boolean)

      set_zuorest_client_timeout

      with_database_error_fallback(fallback: -> { send_invoice_by_email }) do
        if invoices.size == 0
          invoice_download_success = true
          head :not_found
        elsif invoices.size == 1
          invoice = invoices.sole
          invoice_pdf = convert_invoice_to_pdf(invoice)
          invoice_download_success = true
          send_data(invoice_pdf,
            filename: "#{invoice.number}.pdf",
            type: "application/pdf",
            disposition: "attachment",
          )
        else
          transaction_id = T.must(transaction).transaction_id
          zipped_invoices = create_zipped_invoices
          invoice_download_success = true
          send_file(zipped_invoices.path,
            type: "application/zip",
            filename: "#{transaction_id}.zip"
          )
        end
      end
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      GitHub.logger.error(e, log_context)
      GitHub.dogstats.increment("billing.download_invoice_failure.zuorest_http_error")
      head :internal_server_error
    rescue Faraday::TimeoutError => e
      GitHub.logger.error(e, log_context)
      send_invoice_by_email
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      success = !!invoice_download_success
      tags = ["success:#{success}"]
      if success
        tags << "count:#{invoices.size}"
      end
      GitHub.dogstats.distribution("billing.invoice_downloads.dist.time", elapsed, tags:)
      instrument_invoice_downloaded(success: !!invoice_download_success)
    end
  end

  private

  # This set the Zuorest client timeout to 8 seconds, which is less than the application
  # timeout of 10 seconds. This is to reduce the number of Faraday::TimeoutError that could occur.
  sig { void }
  def set_zuorest_client_timeout
    GitHub.zuorest_client.timeout = 8
    GitHub.zuorest_client.open_timeout = 8
  end

  sig { returns(String) }
  def invoice_download_rate_limit_key
    "invoice_download_limit:#{current_user&.id}"
  end

  sig { void }
  def invoice_download_rate_limit_at_limit
    head :too_many_requests
  end

  sig { returns(T::Array[Billing::Zuora::Invoice]) }
  memoize def invoices
    platform_transaction_id = transaction&.platform_transaction_id
    return [] unless platform_transaction_id
    Billing::Zuora::Invoice.invoices_for_transaction(platform_transaction_id, billable_entity: account)
  end

  sig { params(invoice: Billing::Zuora::Invoice).returns(String) }
  def convert_invoice_to_pdf(invoice)
    Base64.decode64(invoice.body)
  end

  sig { returns(Tempfile) }
  def create_zipped_invoices
    zipped_invoices_file = Tempfile.new("#{T.must(transaction).transaction_id}.zip")
    files_to_close = [zipped_invoices_file]
    Zip::File.open(zipped_invoices_file.path, create: true) do |zipfile|
      invoices.each do |invoice|
        with_database_error_fallback(fallback: -> { send_invoice_by_email }) do
          file = Tempfile.new("#{invoice.number}_invoice.pdf", binmode: true)
          file.write(convert_invoice_to_pdf(invoice))
          file.rewind
          files_to_close << file
          zipfile.add("#{invoice.number}.pdf", file.path)
        end
      end
    end

    files_to_close.each do |file|
      file.close
    end

    zipped_invoices_file
  end

  sig { void }
  def send_invoice_by_email
    # The invoice ids might not be available, thus the transaction id provided in the params is used
    EmailInvoicesForTransactionJob.perform_later(transaction_id: params[:transaction_id], emails: [current_user.billing_email])
    instrument_invoice_downloaded(success: false, invoice_sent_by_email: true)
    GitHub.dogstats.increment("billing.invoice_downloads.email_fallback")
    head :gateway_timeout
  end

  sig { returns(Customer) }
  memoize def customer
    T.must(T.must(account).customer)
  end

  sig { returns(T.nilable(Billing::BillingTransaction)) }
  memoize def transaction
    if params[:transaction_id].present?
      T.must(account).billing_transactions.find_by(id: params[:transaction_id])
    else
      nil
    end
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  memoize def find_account_by_type
    if params[:slug].present?
      ::Business.find_by(slug: params[:slug])
    elsif params[:organization_id].present?
      Organization.find_by_login(params[:organization_id])
    elsif params[:user_id]
      User.find_by_login(params[:user_id])
    else
      current_user
    end
  end
  alias :account :find_account_by_type

  sig { returns(T.any(Billing::Types::Account, Symbol)) }
  def target_for_conditional_access
    find_account_by_type || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def ensure_account_exists
    render_404 unless account
  end

  sig { void }
  def ensure_account_manageable_by_user
    render_404 unless account_manageable_by_user? || site_admin?
  end

  sig { returns(T::Boolean) }
  def account_manageable_by_user?
    if T.must(account).business?
      business = T.cast(account, Business)
      business.owner?(current_user) || business.billing_manager?(current_user)
    elsif T.must(account).organization?
      T.cast(account, Organization).billing_manageable_by?(current_user)
    else
      account == current_user
    end
  end

  sig { void }
  def ensure_transaction_exists
    render_404 unless transaction.present?
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def log_context
    {
      "gh.code.namespace" => self.class,
      "gh.billing.billable_entity.id" => account&.id,
      "gh.billing.billable_entity.login" => account&.display_login,
      "gh.billing.billable_entity.type" => account.class.name,
      "gh.billing.customer.id" => account&.customer&.id,
      "gh.billing.zuora.account.id" => account&.customer&.zuora_account_id,
      "gh.billing.billing_transaction.id.id" => transaction&.id,
    }
  end

  sig { params(success: T::Boolean, invoice_sent_by_email: T::Boolean).void }
  def instrument_invoice_downloaded(success:, invoice_sent_by_email: false)
    payload = {
      actor: current_user,
      transaction_id: transaction&.transaction_id,
      invoice_sent_by_email:,
      success:,
    }.tap do |p|
      p[T.must(account).event_prefix] = account
      if success
        p[:invoice_urls] = invoices.inject({}) do |invoice_url_map, invoice|
          invoice_url_map[invoice.number] = zuora_invoice_link(invoice.id)
          invoice_url_map
        end
      end
    end
    GitHub.instrument("billing.invoice_downloaded", payload)
  end

  sig { params(id: String).returns(String) }
  def zuora_invoice_link(id)
    "https://www.zuora.com/platform/apps/com_zuora/invoice/#{id}"
  end
end
