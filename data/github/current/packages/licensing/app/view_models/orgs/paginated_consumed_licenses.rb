# typed: true
# frozen_string_literal: true

class Orgs::PaginatedConsumedLicenses
  include Enumerable

  attr_reader :current_page, :per_page

  def initialize(license_attributer:, page:, per_page: nil)
    @license_attributer = license_attributer
    @current_page = [page.to_i, 1].max
    @per_page = per_page || WillPaginate.per_page
  end

  def each(&block)
    starting_point = (current_page - 1) * per_page

    users = fetch_users(
      starting_point: starting_point,
      limit: per_page,
    )

    emails = fetch_emails(
      starting_point: starting_point + users.size - sorted_user_ids.size,
      limit: per_page - users.size,
    )

    users.each do |user|
      yield Orgs::ConsumedLicenseView.new(display_login: user.display_login)
    end

    emails.each do |email|
      yield Orgs::ConsumedLicenseView.new(email: email)
    end
  end

  def total_count
    license_attributer.unique_count
  end

  def total_pages
    (total_count / per_page.to_f).ceil
  end

  private

  attr_reader :license_attributer

  def fetch_users(starting_point:, limit:)
    user_ids = sorted_user_ids.slice(starting_point, limit) || []

    user_ids.any? ? User.where(id: user_ids) : []
  end

  def fetch_emails(starting_point:, limit:)
    sorted_emails.slice(starting_point, limit) || []
  end

  def sorted_user_ids
    @sorted_user_ids ||= license_attributer.user_ids.to_a.sort
  end

  def sorted_emails
    @sorted_emails ||= license_attributer.emails.to_a.sort
  end
end
