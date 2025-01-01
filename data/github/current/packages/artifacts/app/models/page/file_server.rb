# typed: true
# frozen_string_literal: true

class Page::FileServer < ApplicationRecord::Domain::PagesFromRepositories
  self.table_name = :pages_fileservers
end
