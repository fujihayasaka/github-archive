# typed: true
# frozen_string_literal: true

class ReleaseMention < ApplicationRecord::Domain::Repositories
  belongs_to :release
  belongs_to :user
end
