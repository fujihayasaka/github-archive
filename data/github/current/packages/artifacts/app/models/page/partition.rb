# typed: true
# frozen_string_literal: true

class Page::Partition < ApplicationRecord::Domain::Repositories
  self.table_name = :pages_partitions
end
