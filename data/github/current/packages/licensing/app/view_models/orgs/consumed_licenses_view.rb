# typed: true
# frozen_string_literal: true

class Orgs::ConsumedLicensesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :page

  def page_title
    "Consumed Licenses for #{organization.display_login}"
  end

  def selected_link
    urls.settings_org_billing_path(organization)
  end

  def data_rows
    Orgs::PaginatedConsumedLicenses.new(
      license_attributer: Organization::LicenseAttributer.new(organization),
      page: page,
    )
  end
end
