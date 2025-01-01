# typed: true
# frozen_string_literal: true

class PageUpdate < ApplicationRecord::Domain::Repositories
  self.table_name = :page_updates

  enum :event, { update_event: 0, delete_event: 1, update_subdomain_event: 2 }
end
