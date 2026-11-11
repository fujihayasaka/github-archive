# typed: true
# frozen_string_literal: true

module RepositoryAdvisory::AfterPublication
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))

    scope :after_publication, -> {
      joins(:repository_advisory).
        merge(RepositoryAdvisory.published).
        where("#{quoted_table_name}.created_at > #{RepositoryAdvisory.quoted_table_name}.published_at")
    }
  end

  def async_after_publication?
    async_repository_advisory.then do |repository_advisory|
      repository_advisory.published? &&
        created_at > repository_advisory.published_at
    end
  end

  def after_publication?
    async_after_publication?.sync
  end
end
