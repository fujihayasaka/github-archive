# typed: true
# frozen_string_literal: true

class PullRequestImport < ApplicationRecord::Domain::Imports

  belongs_to :import
  belongs_to :pull_request

  validates_presence_of :import, :pull_request
end
