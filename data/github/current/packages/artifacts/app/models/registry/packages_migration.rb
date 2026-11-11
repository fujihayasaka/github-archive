# typed: true
# frozen_string_literal: true

class Registry::PackagesMigration < ApplicationRecord::Domain::Packages
  self.table_name = :packages_migration

  belongs_to :owner, class_name: "User", required: true

  enum :state, { inProgress: 0, completed: 1 }

  after_commit :send_notification, on: :update

  def send_notification
    if GitHub.enterprise? && self.state == "completed"
      result = {
        enterprise_name: GitHub.global_business.name,
        total_org_count: self.total_org_count,
        failed_org_count: self.failed_org_count,
        total_pkg_count: self.total_pkg_count,
        url: "#{GitHub.url}/enterprises/#{GitHub.global_business.slug}/settings/packages_migration"
      }
      EnterpriseMailer.packages_migration(self.owner, result).deliver_later
    end
  end
end
