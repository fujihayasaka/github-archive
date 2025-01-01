# typed: false
# frozen_string_literal: true

class Orgs::Packages::IndexView < Orgs::OverviewView
  attr_reader :phrase, :organization

  def no_packages?
    return @no_packages if defined? @no_packages
    @no_packages = packages_count.zero?
  end

  def packages_count
    @packages_count ||= packages.size
  end

  def page_title
    "Packages · #{organization.safe_profile_name}"
  end
end
