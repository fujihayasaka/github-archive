# typed: true
# frozen_string_literal: true

class Store < ApplicationRecord::Domain::Repositories
  include GitHub::VexiActor
  include GitRepository::SpokesAdapter
  include Store::DGit
  include Store::SpokesAPI
end
