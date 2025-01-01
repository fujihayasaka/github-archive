# typed: true
# frozen_string_literal: true

module Repositories
  class DcoLabelComponent < ApplicationComponent
    attr_reader :repo, :label_for, :choose_email

    def initialize(repo:, label_for: "", choose_email: false)
      @repo = repo
      @label_for = label_for
      @choose_email = choose_email
    end
  end
end
