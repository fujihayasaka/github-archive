# typed: true
# frozen_string_literal: true

class Page::PagesMigrations < ApplicationRecord::Domain::Repositories
  self.table_name = :pages_migrations
  enum :status, {
    created: 0,
    running: 1,
    succeed: 2,
    failed:  3,
    skipped: 4,
    skipped_page_missing: 5,
    failed_rsync: 6,
    skipped_already_in_azure: 7,
    failed_nil_deployment_revision: 8,
    failed_source_host_not_found: 9,
  }
end
