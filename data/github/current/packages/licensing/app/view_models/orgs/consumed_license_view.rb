# typed: true
# frozen_string_literal: true

class Orgs::ConsumedLicenseView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :display_login, :email

  def display_name
    display_login || email
  end

  def url
    urls.user_path(display_login) if display_login.present?
  end
end
