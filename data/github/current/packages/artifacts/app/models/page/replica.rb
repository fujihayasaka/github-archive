# typed: true
# frozen_string_literal: true

class Page::Replica < ApplicationRecord::Domain::PagesFromRepositories
  self.table_name = :pages_replicas
end
